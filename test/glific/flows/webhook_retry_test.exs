defmodule Glific.Flows.WebhookRetryTest do
  @moduledoc """
  Covers retries of the webhook Oban job: once an attempt has logged a successful result, a
  retry resumes the flow on that result instead of calling the webhook again.
  """
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Ecto.Query, warn: false
  import Mock

  alias Glific.Fixtures
  alias Glific.Flows.Action
  alias Glific.Flows.FlowContext
  alias Glific.Flows.FlowRevision
  alias Glific.Flows.Webhook
  alias Glific.Flows.WebhookLog
  alias Glific.Flows.Webhooks.Registry
  alias Glific.Partners
  alias Glific.Repo
  alias Glific.Seeds.SeedsDev
  alias Glific.WAGroup.WAMessage

  @results %{"score" => "31", "status" => "5"}

  defmodule StubAsyncWebhook do
    use Glific.Flows.Webhooks.Async, name: "stub_async_retry"

    @impl true
    def call(_fields, _ctx) do
      send(self(), :async_dispatched)
      {:ok, %{"success" => true}}
    end
  end

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  @node_uuid "5b3a6a3e-6f32-4b7e-9a1c-2f0d8c1e7a10"

  # A single webhook node whose Success and Failure exits both end the flow, so resuming the
  # parked context exercises the real router.
  defp published_flow_fixture(name) do
    flow = Fixtures.flow_fixture(%{name: name})

    definition = %{
      "uuid" => flow.uuid,
      "name" => name,
      "type" => "messaging",
      "language" => "base",
      "spec_version" => "14.3.0",
      "localization" => %{},
      "_ui" => %{
        "nodes" => %{
          @node_uuid => %{"type" => "split_by_webhook", "position" => %{"top" => 0, "left" => 0}}
        }
      },
      "nodes" => [
        %{
          "uuid" => @node_uuid,
          "actions" => [
            %{
              "uuid" => Ecto.UUID.generate(),
              "type" => "call_webhook",
              "url" => "some url",
              "method" => "POST",
              "headers" => %{},
              "body" => "{}",
              "result_name" => "webhook_result"
            }
          ],
          "router" => %{
            "type" => "switch",
            "operand" => "@webhook.status",
            "result_name" => "",
            "default_category_uuid" => "499bb916-ef3b-4772-9ebc-b569540acaaf",
            "categories" => [
              %{
                "uuid" => "7cd46d6b-0544-4b88-abaa-da5fb03b1cbd",
                "name" => "Success",
                "exit_uuid" => "0e239299-c480-40ab-ac7d-cde64a1620ed"
              },
              %{
                "uuid" => "499bb916-ef3b-4772-9ebc-b569540acaaf",
                "name" => "Failure",
                "exit_uuid" => "79d7ccb2-e481-4414-be9f-6c27357da1fd"
              }
            ],
            "cases" => [
              %{
                "uuid" => "9748478e-4f37-4fc5-9e02-0a94e6bd998a",
                "type" => "has_number_between",
                "category_uuid" => "7cd46d6b-0544-4b88-abaa-da5fb03b1cbd",
                "arguments" => ["200", "299"]
              }
            ]
          },
          "exits" => [
            %{"uuid" => "0e239299-c480-40ab-ac7d-cde64a1620ed", "destination_uuid" => nil},
            %{"uuid" => "79d7ccb2-e481-4414-be9f-6c27357da1fd", "destination_uuid" => nil}
          ]
        }
      ]
    }

    FlowRevision
    |> where([f], f.flow_id == ^flow.id)
    |> update([f], set: [status: "published", definition: ^definition])
    |> Repo.update_all([])

    flow
  end

  defp enqueued_webhook_job(action, context) do
    assert Webhook.execute(action, context) == nil
    [job] = all_enqueued(worker: Webhook, prefix: "global")
    job
  end

  # Stands in for every HTTP webhook node (POST and GET): they share the Tesla response path in
  # Webhook.perform/1, so the retry guard behaves the same for all of them.
  describe "POST webhook" do
    setup attrs do
      test_pid = self()

      Tesla.Mock.mock_global(fn
        %{method: :post} ->
          send(test_pid, :webhook_called)
          %Tesla.Env{status: 200, body: Jason.encode!(@results)}
      end)

      flow = published_flow_fixture("retried webhook")

      {:ok, context} =
        FlowContext.create_flow_context(%{
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          node_uuid: @node_uuid,
          contact_id: Fixtures.contact_fixture(attrs).id,
          organization_id: attrs.organization_id
        })

      action = %Action{
        headers: %{"Accept" => "application/json"},
        method: "POST",
        url: "some url",
        body: Jason.encode!(%{contact: "@contact"})
      }

      job = enqueued_webhook_job(action, Repo.preload(context, [:contact, :flow]))
      %{job: job}
    end

    test "a retry reuses the logged result instead of calling the webhook again", %{job: job} do
      assert :ok = perform_job(Webhook, job.args)
      assert_received :webhook_called

      assert :ok = perform_job(Webhook, job.args, attempt: 2)
      refute_received :webhook_called

      webhook_log = Repo.get!(WebhookLog, job.args["webhook_log_id"])
      assert webhook_log.status_code == 200
      assert webhook_log.response_json == @results
    end

    test "a retry calls the webhook when no earlier attempt logged a result", %{job: job} do
      assert :ok = perform_job(Webhook, job.args, attempt: 2)
      assert_received :webhook_called
    end
  end

  # Stands in for every function webhook node (registered nodes and per-org client webhooks): they
  # share the function-result path in Webhook.perform/1. The poll is used because a duplicate
  # send shows up as an extra wa_messages row.
  describe "send_wa_group_poll webhook" do
    setup attrs do
      Partners.create_credential(%{
        organization_id: attrs.organization_id,
        shortcode: "maytapi",
        keys: %{},
        secrets: %{
          "product_id" => "00000000-0000-0000-0000-000000000000",
          "token" => "11111111-1111-1111-1111-111111111111"
        },
        is_active: true
      })

      attrs.organization_id
      |> Partners.get_organization!()
      |> Partners.fill_cache()

      :ok
    end

    test "a retry after the poll was sent does not send it again", attrs do
      wa_phone = Fixtures.wa_managed_phone_fixture(attrs)
      flow = published_flow_fixture("retried poll")

      wa_group =
        attrs
        |> Map.put(:wa_managed_phone_id, wa_phone.id)
        |> Fixtures.wa_group_with_primary_fixture()

      {:ok, context} =
        FlowContext.create_flow_context(%{
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          node_uuid: @node_uuid,
          wa_group_id: wa_group.id,
          organization_id: attrs.organization_id
        })

      poll = Fixtures.wa_poll_fixture(%{label: "retried_poll"})

      action = %Action{
        method: "FUNCTION",
        url: "send_wa_group_poll",
        headers: %{},
        body: Jason.encode!(%{wa_group: "@wa_group", poll_uuid: "#{poll.uuid}"})
      }

      job = enqueued_webhook_job(action, Repo.preload(context, [:wa_group, :flow]))

      assert :ok = perform_job(Webhook, job.args)
      assert :ok = perform_job(Webhook, job.args, attempt: 2)

      sent_polls =
        WAMessage
        |> where([message], message.wa_group_id == ^wa_group.id and message.type == :poll)
        |> Repo.aggregate(:count)

      assert sent_polls == 1
    end
  end

  # Stands in for every async webhook node (Kaapi speech-to-text, text-to-speech, filesearch):
  # their logged result is the dispatch acknowledgement, and a retry must neither dispatch again
  # nor resume the flow, which stays parked for the callback.
  describe "async webhook" do
    test "a retry after the dispatch was acknowledged does not dispatch again", attrs do
      flow = published_flow_fixture("retried async webhook")

      {:ok, context} =
        FlowContext.create_flow_context(%{
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          node_uuid: @node_uuid,
          contact_id: Fixtures.contact_fixture(attrs).id,
          organization_id: attrs.organization_id
        })

      action = %Action{
        type: "call_webhook",
        method: "FUNCTION",
        url: "stub_async_retry",
        headers: %{},
        body: "{}",
        result_name: "async_result"
      }

      with_mocks([
        {Registry, [:passthrough],
         [
           lookup: fn
             "stub_async_retry" -> StubAsyncWebhook
             name -> :meck.passthrough([name])
           end,
           lookup!: fn _name -> StubAsyncWebhook end,
           async?: fn url -> url == "stub_async_retry" end
         ]}
      ]) do
        context = Repo.preload(context, [:contact, :flow])
        assert {:wait, _parked_context, []} = Action.execute(action, context, [])
        [job] = all_enqueued(worker: Webhook, prefix: "global")

        assert :ok = perform_job(Webhook, job.args)
        assert_received :async_dispatched

        assert :ok = perform_job(Webhook, job.args, attempt: 2)
        refute_received :async_dispatched
      end

      parked_context = Repo.get!(FlowContext, context.id)
      assert parked_context.is_await_result
      assert is_nil(parked_context.completed_at)
    end
  end
end
