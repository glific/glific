defmodule Glific.Flows.Webhooks.GeolocationTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.Flows.{
    Action,
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

  defp build_context(attrs) do
    flow_attrs = %{
      flow_id: 1,
      flow_uuid: Ecto.UUID.generate(),
      contact_id: Fixtures.contact_fixture(attrs).id,
      organization_id: attrs.organization_id
    }

    {:ok, context} = FlowContext.create_flow_context(flow_attrs)
    {Repo.preload(context, [:contact, :flow]), flow_attrs}
  end

  describe "geolocation" do
    test "happy path returns success with address components", attrs do
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
        body: Jason.encode!(%{lat: "19.0760", long: "72.8777"})
      }

      assert Webhook.execute(action, context) == nil

      Oban.drain_queue(queue: :webhook)

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log.status == "Success"
      assert log.response_json["success"] == true
      assert log.response_json["city"] == "Mumbai"
    end

    test "failure - API returns ZERO_RESULTS records error in log", attrs do
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
        body: Jason.encode!(%{lat: "0.0000", long: "0.0000"})
      }

      assert Webhook.execute(action, context) == nil

      Oban.drain_queue(queue: :webhook)

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      # Either the response_json indicates failure, or an error string was returned
      assert log.error != nil or
               (is_map(log.response_json) and log.response_json["success"] != true) or
               is_binary(log.response_json)
    end
  end
end
