defmodule Glific.Flows.Webhooks.ParseViaChatGptTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Glific.WebhookTestHelpers

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.Flow,
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

  describe "parse_via_chat_gpt" do
    test "happy path returns success and parsed_msg in webhook log and resumes flow", attrs do
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
          }),
        result_name: "filesearch"
      }

      assert Webhook.execute(action, context) == nil

      [%{priority: 0, queue: "gpt_webhook_queue"} | _] =
        all_enqueued(worker: Webhook, prefix: "global")

      Oban.drain_queue(queue: :gpt_webhook_queue)

      # WebhookLog assertions — verify the webhook itself succeeded
      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log.status == "Success"
      assert log.response_json["success"] == true
      assert log.response_json["parsed_msg"] != nil

      # Flow execution assertion — verify the flow resumed on the success branch.
      # The call_and_wait success node sends "@results.filesearch.message"; since
      # the parse_via_chat_gpt result has no "message" key, the template expression
      # is rendered as-is, proving the flow engine advanced past the webhook node.
      message = await_flow_message(context.contact_id, "@results.filesearch.message")
      assert message.body == "@results.filesearch.message"
    end

    test "failure - OpenAI returns 500, webhook log records error and flow takes failure branch",
         attrs do
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
          }),
        result_name: "filesearch"
      }

      assert Webhook.execute(action, context) == nil
      Oban.drain_queue(queue: :gpt_webhook_queue)

      # WebhookLog assertions — verify the webhook recorded the failure
      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.status_code == 500 or log.error != nil

      # Flow execution assertion — webhook failure routes to the Failure branch
      message = await_flow_message(context.contact_id, "failure")
      assert message.body == "failure"
    end
  end
end
