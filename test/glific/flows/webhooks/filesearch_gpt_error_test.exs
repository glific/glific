defmodule Glific.Flows.Webhooks.FilesearchGptErrorTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo
  import Mock

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.Flow,
    Flows.FlowContext,
    Flows.WebhookLog,
    Flows.Webhooks.Errors,
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

  defp filesearch_action do
    %Action{
      type: "call_webhook",
      method: "FUNCTION",
      url: "filesearch-gpt",
      headers: %{"Accept" => "application/json"},
      body: Jason.encode!(%{"question" => "tell me about glific", "assistant_id" => "asst_123"}),
      result_name: "filesearch"
    }
  end

  defp voice_action do
    %Action{
      type: "call_webhook",
      method: "FUNCTION",
      url: "voice-filesearch-gpt",
      headers: %{"Accept" => "application/json"},
      body:
        Jason.encode!(%{
          "speech" => "https://example.com/audio.ogg",
          "assistant_id" => "asst_123"
        }),
      result_name: "filesearch"
    }
  end

  # The webhook parks the flow (Action.execute), then the worker dispatches the module,
  # which fails because Kaapi is not configured. Returns the SystemError exception (if any)
  # captured while the worker runs.
  defp park_and_drain(action, context) do
    test_pid = self()

    exception =
      with_mock Appsignal, [:passthrough],
        send_error: fn exception, _stack, _configurator ->
          send(test_pid, {:appsignal_error, exception})
          :ok
        end do
        assert {:wait, _parked, []} = Action.execute(action, context, [])
        Oban.drain_queue(queue: :gpt_webhook_queue)
      end

    exception
  end

  describe "filesearch-gpt when kaapi is not configured" do
    test "the webhook log records the Kaapi-not-active error", %{organization_id: org_id} do
      park_and_drain(filesearch_action(), build_context(org_id))

      webhook_log = Repo.get_by(WebhookLog, %{url: "filesearch-gpt"})
      assert webhook_log.error == "Kaapi is not active"
    end

    test "reports SystemError to AppSignal", %{organization_id: org_id} do
      park_and_drain(filesearch_action(), build_context(org_id))

      assert_received {:appsignal_error, %Errors.SystemError{} = exception}
      assert Exception.message(exception) == "Webhook system_error from filesearch-gpt"
    end
  end

  describe "voice-filesearch-gpt when kaapi is not configured" do
    test "the webhook log records the Kaapi-not-active error", %{organization_id: org_id} do
      park_and_drain(voice_action(), build_context(org_id))

      webhook_log = Repo.get_by(WebhookLog, %{url: "voice-filesearch-gpt"})
      assert webhook_log.error == "Kaapi is not active"
    end

    test "reports SystemError to AppSignal", %{organization_id: org_id} do
      park_and_drain(voice_action(), build_context(org_id))

      assert_received {:appsignal_error, %Errors.SystemError{} = exception}
      assert Exception.message(exception) == "Webhook system_error from voice-filesearch-gpt"
    end
  end
end
