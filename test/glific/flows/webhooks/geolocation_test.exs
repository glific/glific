defmodule Glific.Flows.Webhooks.GeolocationTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Glific.WebhookTestHelpers

  alias Glific.Flows.{
    Action,
    Flow,
    FlowContext,
    Webhook,
    WebhookLog
  }

  alias Glific.{
    Fixtures,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  # Build a FlowContext linked to the real call_and_wait flow so that
  # FlowContext.wakeup_one/2 can load the flow and advance it after the
  # webhook job completes.
  defp build_context(attrs) do
    contact = Fixtures.contact_fixture(attrs)
    flow = Flow.get_loaded_flow(attrs.organization_id, "published", %{keyword: "call_and_wait"})
    [node | _] = flow.nodes

    flow_attrs = %{
      flow_id: flow.id,
      contact_id: contact.id,
      organization_id: attrs.organization_id
    }

    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_id: flow.id,
        flow_uuid: flow.uuid,
        organization_id: attrs.organization_id,
        node_uuid: node.uuid,
        is_await_result: true
      })

    {Repo.preload(context, [:contact, :flow]), flow_attrs}
  end

  describe "geolocation" do
    test "happy path returns success with address components and resumes flow", attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "results" => [
                  %{
                    "address_components" => [
                      %{"long_name" => "Mumbai", "types" => ["locality"]},
                      %{
                        "long_name" => "Maharashtra",
                        "types" => ["administrative_area_level_1"]
                      },
                      %{"long_name" => "India", "types" => ["country"]}
                    ],
                    "formatted_address" => "Mumbai, Maharashtra, India"
                  }
                ],
                "status" => "OK"
              })
          }
      end)

      {context, flow_attrs} = build_context(attrs)

      action = %Action{
        method: "FUNCTION",
        url: "geolocation",
        headers: %{},
        body: Jason.encode!(%{lat: "19.0760", long: "72.8777"}),
        result_name: "filesearch"
      }

      assert Webhook.execute(action, context) == nil

      Oban.drain_queue(queue: :webhook)

      # WebhookLog assertions — verify the webhook itself succeeded
      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log.status == "Success"
      assert log.response_json["success"] == true
      assert log.response_json["city"] == "Mumbai"

      # Flow execution assertion — verify the flow resumed on the success branch.
      # The call_and_wait success node sends "@results.filesearch.message"; since
      # the geolocation result has no "message" key, the template expression is
      # rendered as-is, proving the flow engine advanced past the webhook node.
      message = await_flow_message(context.contact_id, "@results.filesearch.message")
      assert message.body == "@results.filesearch.message"
    end

    test "failure - API returns ZERO_RESULTS records error in log and flow takes failure branch",
         attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "results" => [],
                "status" => "ZERO_RESULTS"
              })
          }
      end)

      {context, flow_attrs} = build_context(attrs)

      action = %Action{
        method: "FUNCTION",
        url: "geolocation",
        headers: %{},
        body: Jason.encode!(%{lat: "0.0000", long: "0.0000"}),
        result_name: "filesearch"
      }

      assert Webhook.execute(action, context) == nil

      Oban.drain_queue(queue: :webhook)

      # WebhookLog assertions — verify the webhook recorded the failure
      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil

      assert log.error != nil

      # Flow execution assertion — non-map result triggers the Failure branch
      message = await_flow_message(context.contact_id, "failure")
      assert message.body == "failure"
    end
  end
end
