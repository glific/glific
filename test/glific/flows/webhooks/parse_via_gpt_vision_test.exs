defmodule Glific.Flows.Webhooks.ParseViaGptVisionTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.FlowContext,
    Flows.Webhook,
    Flows.WebhookLog,
    Messages,
    Repo,
    Seeds.SeedsDev
  }

  import Mock

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

  describe "parse_via_gpt_vision" do
    test "happy path returns success", attrs do
      with_mock(
        Messages,
        validate_media: fn _, _ -> %{is_valid: true, message: "success"} end
      ) do
        Tesla.Mock.mock(fn
          %{url: "https://api.openai.com/v1/chat/completions"} ->
            %Tesla.Env{
              status: 200,
              body: %{
                "choices" => [
                  %{
                    "message" => %{
                      "content" =>
                        "{\"summary\":\"A car on a road\",\"detected_objects\":[\"car\",\"road\"]}"
                    }
                  }
                ]
              }
            }
        end)

        {context, flow_attrs} = build_context(attrs)

        action = %Action{
          method: "FUNCTION",
          url: "parse_via_gpt_vision",
          headers: %{"Content-Type" => "application/json"},
          body:
            Jason.encode!(%{
              prompt: "Describe this image",
              url: "https://example.com/image.jpg",
              model: "gpt-4o"
            })
        }

        assert Webhook.execute(action, context) == nil
        Oban.drain_queue(queue: :gpt_webhook_queue)

        log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
        assert log.status == "Success"
        assert log.response_json["success"] == true
      end
    end

    test "failure - API returns 500 error", attrs do
      with_mock(
        Messages,
        validate_media: fn _, _ -> %{is_valid: true, message: "success"} end
      ) do
        Tesla.Mock.mock(fn
          %{url: "https://api.openai.com/v1/chat/completions"} ->
            %Tesla.Env{
              status: 500,
              body: Jason.encode!(%{"error" => %{"message" => "Internal Server Error"}})
            }
        end)

        {context, flow_attrs} = build_context(attrs)

        action = %Action{
          method: "FUNCTION",
          url: "parse_via_gpt_vision",
          headers: %{"Content-Type" => "application/json"},
          body:
            Jason.encode!(%{
              prompt: "Describe this image",
              url: "https://example.com/image.jpg",
              model: "gpt-4o"
            })
        }

        assert Webhook.execute(action, context) == nil
        Oban.drain_queue(queue: :gpt_webhook_queue)

        log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
        assert log != nil
        assert log.status_code >= 400 or log.error != nil
      end
    end
  end
end
