defmodule Glific.Flows.Webhooks.FilesearchGptErrorTest do
  use Glific.DataCase, async: false
  import Mock

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.Flow,
    Flows.FlowContext,
    Flows.Webhooks.Errors,
    Flows.WebhookLog,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  defp build_context(org_id) do
    contact = Fixtures.contact_fixture(%{organization_id: org_id})
    flow = Flow.get_loaded_flow(org_id, "published", %{keyword: "call_and_wait"})
    [node | _] = flow.nodes

    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_id: flow.id,
        flow_uuid: flow.uuid,
        uuid_map: %{},
        organization_id: org_id,
        node_uuid: node.uuid
      })

    Repo.preload(context, [:flow, :contact])
  end

  describe "filesearch-gpt when kaapi is not configured" do
    test "logs descriptive error and returns failure message", %{organization_id: org_id} do
      context = build_context(org_id)

      action = %Action{
        type: "call_webhook",
        method: "FUNCTION",
        url: "filesearch-gpt",
        headers: %{"Accept" => "application/json"},
        body:
          Jason.encode!(%{"question" => "tell me about glific", "assistant_id" => "asst_123"}),
        result_name: "filesearch",
        node_uuid: "Test UUID"
      }

      assert {:ok, _flow_context, [message]} = Action.execute(action, context, [])
      assert message.body == "Failure"

      webhook_log = Repo.get_by(WebhookLog, %{url: "filesearch-gpt"})
      assert webhook_log.error == "Kaapi is not active"
    end

    test "reports SystemError to AppSignal", %{organization_id: org_id} do
      context = build_context(org_id)

      action = %Action{
        type: "call_webhook",
        method: "FUNCTION",
        url: "filesearch-gpt",
        headers: %{"Accept" => "application/json"},
        body:
          Jason.encode!(%{"question" => "tell me about glific", "assistant_id" => "asst_123"}),
        result_name: "filesearch",
        node_uuid: "Test UUID"
      }

      test_pid = self()

      with_mock Appsignal, [:passthrough],
        send_error: fn exception, _stack, _configurator ->
          send(test_pid, {:appsignal_error, exception})
          :ok
        end do
        Action.execute(action, context, [])
      end

      assert_received {:appsignal_error, %Errors.SystemError{} = exception}
      assert Exception.message(exception) == "Webhook system_error from unified-llm-call"

      webhook_log = Repo.get_by(WebhookLog, %{url: "filesearch-gpt"})
      assert webhook_log.error == "Kaapi is not active"
    end
  end

  describe "voice-filesearch-gpt when kaapi is not configured" do
    test "logs descriptive error and returns failure message", %{organization_id: org_id} do
      context = build_context(org_id)

      action = %Action{
        type: "call_webhook",
        method: "FUNCTION",
        url: "voice-filesearch-gpt",
        headers: %{"Accept" => "application/json"},
        body:
          Jason.encode!(%{
            "speech" => "https://example.com/audio.ogg",
            "assistant_id" => "asst_123"
          }),
        result_name: "filesearch",
        node_uuid: "Test UUID"
      }

      assert {:ok, _flow_context, [message]} = Action.execute(action, context, [])
      assert message.body == "Failure"

      webhook_log = Repo.get_by(WebhookLog, %{url: "voice-filesearch-gpt"})
      assert webhook_log.error == "Kaapi is not active"
    end

    test "reports SystemError to AppSignal", %{organization_id: org_id} do
      context = build_context(org_id)

      action = %Action{
        type: "call_webhook",
        method: "FUNCTION",
        url: "voice-filesearch-gpt",
        headers: %{"Accept" => "application/json"},
        body:
          Jason.encode!(%{
            "speech" => "https://example.com/audio.ogg",
            "assistant_id" => "asst_123"
          }),
        result_name: "filesearch",
        node_uuid: "Test UUID"
      }

      test_pid = self()

      with_mock Appsignal, [:passthrough],
        send_error: fn exception, _stack, _configurator ->
          send(test_pid, {:appsignal_error, exception})
          :ok
        end do
        Action.execute(action, context, [])
      end

      assert_received {:appsignal_error, %Errors.SystemError{} = exception}
      assert Exception.message(exception) == "Webhook system_error from unified-voice-llm-call"

      webhook_log = Repo.get_by(WebhookLog, %{url: "voice-filesearch-gpt"})
      assert webhook_log.error == "Kaapi is not active"
    end
  end
end
