defmodule Glific.Flows.Webhooks.ParseViaChatGptTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.FlowContext,
    Flows.Webhook,
    Flows.WebhookLog,
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

  describe "parse_via_chat_gpt" do
    test "happy path returns success and parsed_msg in webhook log", attrs do
      Tesla.Mock.mock(fn
        %{method: :post, url: "https://api.openai.com/v1/chat/completions"} ->
          %Tesla.Env{
            status: 200,
            body: %{
              "choices" => [
                %{"message" => %{"content" => "This is the parsed message"}}
              ]
            }
          }
      end)

      {context, flow_attrs} = build_context(attrs)

      action = %Action{
        method: "FUNCTION",
        url: "parse_via_chat_gpt",
        headers: %{"Content-Type" => "application/json"},
        body:
          Jason.encode!(%{
            question_text: "Summarize this",
            gpt_model: "gpt-4",
            prompt: "Be concise"
          })
      }

      assert Webhook.execute(action, context) == nil

      [%{priority: 0, queue: "gpt_webhook_queue"} | _] =
        all_enqueued(worker: Webhook, prefix: "global")

      Oban.drain_queue(queue: :gpt_webhook_queue)

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log.status == "Success"
      assert log.response_json["success"] == true
      assert log.response_json["parsed_msg"] != nil
    end

    test "failure - OpenAI returns 500, webhook log records error", attrs do
      Tesla.Mock.mock(fn
        %{method: :post, url: "https://api.openai.com/v1/chat/completions"} ->
          %Tesla.Env{
            status: 500,
            body: Jason.encode!(%{"error" => %{"message" => "Internal Server Error"}})
          }
      end)

      {context, flow_attrs} = build_context(attrs)

      action = %Action{
        method: "FUNCTION",
        url: "parse_via_chat_gpt",
        headers: %{"Content-Type" => "application/json"},
        body:
          Jason.encode!(%{
            question_text: "Summarize this",
            gpt_model: "gpt-4",
            prompt: "Be concise"
          })
      }

      assert Webhook.execute(action, context) == nil
      Oban.drain_queue(queue: :gpt_webhook_queue)

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.status_code == 500 or log.error != nil
    end
  end
end
