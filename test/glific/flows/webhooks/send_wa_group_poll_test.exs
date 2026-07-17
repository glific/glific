defmodule Glific.Flows.Webhooks.SendWaGroupPollTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Ecto.Query, warn: false

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.FlowContext,
    Flows.FlowRevision,
    Flows.Webhook,
    Flows.WebhookLog,
    Flows.Webhooks.Dispatcher,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)

    Partners.create_credential(%{
      organization_id: 1,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{
        "product_id" => "00000000-0000-0000-0000-000000000000",
        "token" => "11111111-1111-1111-1111-111111111111"
      },
      is_active: true
    })

    Partners.get_organization!(1) |> Partners.fill_cache()
    :ok
  end

  defp build_wa_group_context(attrs) do
    wa_phone = Fixtures.wa_managed_phone_fixture(attrs)

    flow = Fixtures.flow_fixture(%{name: "polls"})

    FlowRevision
    |> where([f], f.flow_id == ^flow.id)
    |> update([f], set: [status: "published"])
    |> Repo.update_all([])

    wa_group =
      Fixtures.wa_group_with_primary_fixture(Map.put(attrs, :wa_managed_phone_id, wa_phone.id))

    flow_attrs = %{
      flow_id: flow.id,
      flow_uuid: flow.uuid,
      wa_group_id: wa_group.id,
      organization_id: attrs.organization_id
    }

    {:ok, context} = FlowContext.create_flow_context(flow_attrs)
    context = Repo.preload(context, [:wa_group, :flow])

    {context, flow_attrs, wa_phone}
  end

  describe "send_wa_group_poll" do
    test "happy path - successfully sends poll to WA group", attrs do
      Tesla.Mock.mock(fn
        %{method: :post, url: "https://api.maytapi.com/api/" <> _} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "success" => true,
               "data" => %{
                 "chatId" => "120363238104@g.us",
                 "msgId" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d"
               }
             }
           }}
      end)

      poll = Fixtures.wa_poll_fixture(%{label: "poll_a"})
      {context, flow_attrs, _wa_phone} = build_wa_group_context(attrs)

      action = %Action{
        method: "FUNCTION",
        url: "send_wa_group_poll",
        headers: %{},
        body: Jason.encode!(%{wa_group: "@wa_group", poll_uuid: "#{poll.uuid}"})
      }

      assert Webhook.execute(action, context) == nil

      assert_enqueued(worker: Webhook, prefix: "global")

      [job] = all_enqueued(worker: Webhook, prefix: "global")
      assert job.queue == "webhook"

      Oban.drain_queue(queue: :webhook)

      # WebhookLog assertion — verify the poll was dispatched successfully.
      # Note: flow-level execution assertions are not added here because this
      # is a WA group flow context (not a contact flow). WA group flows send
      # messages to the group rather than to a contact, and there is no
      # await_flow_message-style helper for WA group messages. The WebhookLog
      # status is the authoritative signal for this webhook type.
      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.status == "Success"
    end

    test "failure - poll UUID not found", attrs do
      nonexistent_poll_uuid = Ecto.UUID.generate()
      {context, flow_attrs, _wa_phone} = build_wa_group_context(attrs)

      action = %Action{
        method: "FUNCTION",
        url: "send_wa_group_poll",
        headers: %{},
        body: Jason.encode!(%{wa_group: "@wa_group", poll_uuid: nonexistent_poll_uuid})
      }

      assert Webhook.execute(action, context) == nil

      Oban.drain_queue(queue: :webhook)

      # WebhookLog assertion — verify the error was recorded.
      # See happy path test for the note on why flow-level assertions are omitted.
      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.error != nil
    end
  end

  # Dispatch-level test: exercises call/2 validation branches (invalid wa_group / poll_uuid /
  # unknown wa_group) and the success path directly via the Dispatcher.
  describe "send_wa_group_poll dispatch" do
    test "validates inputs and sends the poll", attrs do
      assert {:error, _type, "wa_group is invalid"} =
               Dispatcher.dispatch("send_wa_group_poll", %{})

      assert {:error, _type, "poll_uuid is invalid"} =
               Dispatcher.dispatch("send_wa_group_poll", %{
                 "wa_group" => %{"id" => 0},
                 "organization_id" => attrs.organization_id
               })

      poll = Fixtures.wa_poll_fixture(%{label: "poll_a"})

      assert {:error, :unknown, message} =
               Dispatcher.dispatch("send_wa_group_poll", %{
                 "wa_group" => %{"id" => 0},
                 "organization_id" => attrs.organization_id,
                 "poll_uuid" => poll.uuid
               })

      assert message =~ "Resource not found"

      Tesla.Mock.mock(fn
        %{method: :post, url: "https://api.maytapi.com/api/" <> _} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{"success" => true, "data" => %{"chatId" => "1@g.us", "msgId" => "abc"}}
           }}
      end)

      wa_phone = Fixtures.wa_managed_phone_fixture(attrs)

      wa_group =
        Fixtures.wa_group_with_primary_fixture(Map.put(attrs, :wa_managed_phone_id, wa_phone.id))

      assert {:ok, %{success: true, poll: _}} =
               Dispatcher.dispatch("send_wa_group_poll", %{
                 "wa_group" => %{"id" => wa_group.id},
                 "organization_id" => attrs.organization_id,
                 "poll_uuid" => poll.uuid
               })
    end
  end
end
