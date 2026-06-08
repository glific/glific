defmodule Glific.Flows.Webhooks.TextToSpeechTest do
  @moduledoc """
  Regression safety net for the `text_to_speech` async Kaapi webhook.

  Covers:
  1. Happy-path callback round-trip: Kaapi POSTs success → flow resumes on the success route.
  2. Failure callback: Kaapi POSTs success=false → flow resumes on the failure route.
  3. Timeout: outbound Kaapi request times out → WebhookLog records the error.
  """
  use GlificWeb.ConnCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Flows.Flow,
    Flows.FlowContext,
    Flows.Webhook,
    Flows.WebhookLog,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  alias Glific.Flows.Action

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

    Partners.get_organization!(1) |> Partners.fill_cache()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Helpers — build a FlowContext waiting for the Kaapi callback
  # ---------------------------------------------------------------------------

  defp build_await_context(organization_id) do
    contact = Fixtures.contact_fixture(%{organization_id: organization_id})
    webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})
    flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
    [node | _] = flow.nodes

    {:ok, _context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_id: flow.id,
        flow_uuid: flow.uuid,
        uuid_map: %{},
        organization_id: organization_id,
        wakeup_at: DateTime.add(DateTime.utc_now(), 60),
        is_await_result: true,
        node_uuid: node.uuid
      })

    {contact, webhook_log, flow}
  end

  defp build_callback_params(organization_id, flow_id, contact_id, webhook_log_id, success, message) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    sig_payload = %{
      "organization_id" => organization_id,
      "flow_id" => flow_id,
      "contact_id" => contact_id,
      "timestamp" => timestamp
    }

    signature = Glific.signature(organization_id, Jason.encode!(sig_payload), timestamp)

    %{
      "metadata" => %{
        "organization_id" => organization_id,
        "flow_id" => flow_id,
        "contact_id" => contact_id,
        "signature" => signature,
        "timestamp" => timestamp,
        "webhook_log_id" => webhook_log_id,
        # The call_and_wait flow sends @results.filesearch.message — match it here
        # so the flow's send_msg node resolves to the expected message body.
        "result_name" => "filesearch"
      },
      "data" => %{
        "response" => %{
          "conversation_id" => "conv_tts_test_123",
          "output" => %{
            "type" => "text",
            "content" => %{"value" => message}
          }
        }
      },
      "success" => success
    }
  end

  # ---------------------------------------------------------------------------
  # Async helpers — wait for flow resume to propagate
  # ---------------------------------------------------------------------------

  @await_attempts 50
  @await_interval_ms 100

  defp await_flow_message(contact_id, expected_body) do
    await_flow_resume_tasks()
    await_flow_message(contact_id, expected_body, @await_attempts)
  end

  defp await_flow_resume_tasks(attempts \\ 50)
  defp await_flow_resume_tasks(0), do: flunk("Timed out waiting for flow resume task")

  defp await_flow_resume_tasks(attempts) do
    case Supervisor.count_children(Glific.TaskSupervisor) do
      %{active: 0} ->
        :ok

      _ ->
        Process.sleep(@await_interval_ms)
        await_flow_resume_tasks(attempts - 1)
    end
  end

  defp await_flow_message(contact_id, expected_body, 0) do
    flunk("Timed out waiting for message #{inspect(expected_body)} for contact #{contact_id}")
  end

  defp await_flow_message(contact_id, expected_body, attempts) do
    case Glific.Messages.list_messages(%{
           filter: %{contact_id: contact_id},
           opts: %{limit: 1, order: :desc}
         }) do
      [%{body: ^expected_body} = msg | _] ->
        msg

      _ ->
        Process.sleep(@await_interval_ms)
        await_flow_message(contact_id, expected_body, attempts - 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "text_to_speech" do
    test "happy path - Kaapi callback with audio URL resumes flow on success route", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{status: 200, body: %{"job_id" => "tts-happy-123"}}
      end)

      {contact, webhook_log, flow} = build_await_context(organization_id)

      expected_message = "https://storage.googleapis.com/glific-media-bucket/test.ogg"

      params =
        build_callback_params(
          organization_id,
          flow.id,
          contact.id,
          webhook_log.id,
          true,
          expected_message
        )

      conn = post(conn, "/webhook/flow_resume", params)
      assert json_response(conn, 200) == ""

      message = await_flow_message(contact.id, expected_message)
      assert message.body == expected_message
    end

    test "failure callback - Kaapi signals failure, flow resumes on failure route", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      {contact, webhook_log, flow} = build_await_context(organization_id)

      failure_params =
        build_callback_params(
          organization_id,
          flow.id,
          contact.id,
          webhook_log.id,
          false,
          "Kaapi TTS failed"
        )

      # Add failure-specific fields on top of the base params
      failure_params =
        Map.merge(failure_params, %{
          "error_type" => "tts_failed",
          "reason" => "Kaapi TTS failed"
        })

      conn = post(conn, "/webhook/flow_resume", failure_params)
      assert json_response(conn, 200) == ""

      message = await_flow_message(contact.id, "failure")
      assert message.body == "failure"
    end

    test "timeout - outbound Kaapi TTS request times out, WebhookLog records the error", attrs do
      Tesla.Mock.mock(fn _ -> {:error, :timeout} end)

      flow_attrs = %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: Fixtures.contact_fixture(attrs).id,
        organization_id: attrs.organization_id
      }

      {:ok, context} = FlowContext.create_flow_context(flow_attrs)
      context = Repo.preload(context, [:contact, :flow])

      action = %Action{
        headers: %{"Accept" => "application/json"},
        method: "FUNCTION",
        url: "text_to_speech",
        body: Jason.encode!(%{text: "Hello world"})
      }

      assert Webhook.execute(action, context) == nil
      assert_enqueued(worker: Webhook, prefix: "global")
      Oban.drain_queue(queue: :gpt_webhook_queue)

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.error != nil
    end
  end
end
