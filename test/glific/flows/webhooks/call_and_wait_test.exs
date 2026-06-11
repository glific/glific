defmodule Glific.Flows.Webhooks.CallAndWaitTest do
  use GlificWeb.ConnCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Glific.WebhookTestHelpers

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.Flow,
    Flows.Webhook,
    Flows.WebhookLog,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    SeedsDev.seed_organizations()

    {:ok, _credential} =
      Partners.create_credential(%{
        organization_id: 1,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"},
        is_active: true
      })

    :ok
  end

  describe "call_and_wait" do
    test "happy path - flow resumes with AI response on success callback", %{
      conn: %{assigns: %{organization_id: org_id}} = conn
    } do
      {contact, webhook_log, flow} = build_await_context(org_id)

      params =
        build_old_format_callback_params(
          org_id,
          flow.id,
          contact.id,
          webhook_log.id,
          true,
          "AI response from Kaapi assistant"
        )

      conn = post(conn, "/webhook/flow_resume", params)
      assert json_response(conn, 200) == ""

      message = await_flow_message(contact.id, "AI response from Kaapi assistant")
      assert message.body == "AI response from Kaapi assistant"
    end

    test "failure callback - flow routes to failure branch", %{
      conn: %{assigns: %{organization_id: org_id}} = conn
    } do
      {contact, webhook_log, flow} = build_await_context(org_id)

      params =
        build_old_format_callback_params(
          org_id,
          flow.id,
          contact.id,
          webhook_log.id,
          false,
          "Kaapi error: response generation failed"
        )

      conn = post(conn, "/webhook/flow_resume", params)
      assert json_response(conn, 200) == ""

      message = await_flow_message(contact.id, "failure")
      assert message.body == "failure"

      updated_log = Repo.get!(WebhookLog, webhook_log.id)
      assert updated_log.response_json["message"] == "Kaapi error: response generation failed"
      assert updated_log.response_json["success"] == false
    end

    test "timeout - outbound Kaapi request times out, flow routes to failure branch", %{
      conn: %{assigns: %{organization_id: org_id}} = _conn
    } do
      Tesla.Mock.mock(fn _ -> {:error, :timeout} end)

      contact = Fixtures.contact_fixture(%{organization_id: org_id})
      flow = Flow.get_loaded_flow(org_id, "published", %{keyword: "call_and_wait"})

      {context, flow_filter} = build_flow_context(org_id, contact.id)

      action = %Action{
        method: "FUNCTION",
        url: "call_and_wait",
        headers: %{"X-API-KEY" => "sk_test_key", "Content-Type" => "application/json"},
        body:
          Jason.encode!(%{
            question: "test question",
            flow_id: flow.id,
            contact_id: contact.id,
            organization_id: org_id,
            result_name: "response"
          })
      }

      assert Webhook.execute(action, context) == nil

      [job | _] = all_enqueued(worker: Webhook, prefix: "global")
      assert job.queue == "gpt_webhook_queue"

      Oban.drain_queue(queue: :gpt_webhook_queue)

      # The Oban worker calls handle/3 with action.result_name == nil (the %Action{}
      # struct has no result_name set), so handle/3 routes to the FAILURE branch
      # via FlowContext.wakeup_one with a "Failure" temp message.
      message = await_flow_message(contact.id, "failure")
      assert message.body == "failure"

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_filter}))
      assert log != nil
      assert log.error != nil
    end
  end
end
