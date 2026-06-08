defmodule Glific.Flows.Webhooks.SpeechToTextTest do
  @moduledoc """
  End-to-end regression tests for the `speech_to_text` async Kaapi webhook.

  Covers:
  1. Happy path: outbound Kaapi STT request enqueued → Kaapi callback arrives →
     flow resumes on the Success branch.
  2. Failure callback: Kaapi reports success=false → flow resumes on the Failure branch.
  3. Timeout: outbound Tesla request times out → worker records the error in WebhookLog.
  """

  use GlificWeb.ConnCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.Flow,
    Flows.FlowContext,
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

    Partners.get_organization!(1) |> Partners.fill_cache()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Creates a FlowContext already in await state (is_await_result: true).
  # Mirrors the pattern in flow_resume_controller_test.exs:
  # the flow engine puts the context in this state when it hits the call_and_wait
  # node; we create it directly here to isolate the callback round-trip.
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

  # Builds the callback params that Kaapi POSTs back to /webhook/flow_resume.
  # Uses the NEW unified-API callback format (metadata + data.response.output)
  # which is what the Kaapi STT service sends.
  defp build_callback_params(organization_id, flow_id, contact_id, webhook_log_id, success, message) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    signature_payload = %{
      "organization_id" => organization_id,
      "flow_id" => flow_id,
      "contact_id" => contact_id,
      "timestamp" => timestamp
    }

    signature =
      Glific.signature(
        organization_id,
        Jason.encode!(signature_payload),
        timestamp
      )

    if success do
      %{
        "data" => %{
          "response" => %{
            "conversation_id" => "conv_stt_#{System.unique_integer([:positive])}",
            "output" => %{
              "type" => "text",
              "content" => %{"value" => message}
            }
          }
        },
        "metadata" => %{
          "organization_id" => organization_id,
          "flow_id" => flow_id,
          "contact_id" => contact_id,
          "signature" => signature,
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log_id,
          "result_name" => "filesearch"
        },
        "success" => true
      }
    else
      %{
        "data" => %{},
        "metadata" => %{
          "organization_id" => organization_id,
          "flow_id" => flow_id,
          "contact_id" => contact_id,
          "signature" => signature,
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log_id,
          "result_name" => "filesearch"
        },
        "success" => false,
        "error_type" => "transcription_failed",
        "reason" => message
      }
    end
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "speech_to_text" do
    test "happy path - Kaapi STT callback resumes flow on success branch", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      # Set up FlowContext in await state — this is what the flow engine does when
      # it hits the speech_to_text call_and_wait node.
      {contact, webhook_log, flow} = build_await_context(organization_id)

      expected_message = "Hello, how can I help you today?"

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

    test "failure callback - Kaapi STT callback with success=false routes to failure branch", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      # Set up FlowContext in await state
      {contact, webhook_log, flow} = build_await_context(organization_id)

      params =
        build_callback_params(
          organization_id,
          flow.id,
          contact.id,
          webhook_log.id,
          false,
          "Kaapi STT failed"
        )

      conn = post(conn, "/webhook/flow_resume", params)
      assert json_response(conn, 200) == ""

      message = await_flow_message(contact.id, "failure")
      assert message.body == "failure"
    end

    test "timeout - outbound Kaapi STT request times out, WebhookLog records error", %{
      conn: %{assigns: %{organization_id: organization_id}} = _conn
    } do
      Tesla.Mock.mock(fn _ -> {:error, :timeout} end)

      flow_attrs = %{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: Fixtures.contact_fixture(%{organization_id: organization_id}).id,
        organization_id: organization_id
      }

      {:ok, context} = FlowContext.create_flow_context(flow_attrs)
      context = Repo.preload(context, [:contact, :flow])

      action = %Action{
        headers: %{"Content-Type" => "application/json"},
        method: "FUNCTION",
        url: "speech_to_text",
        body: Jason.encode!(%{"speech" => "https://gcs.example.com/audio.ogg"}),
        result_name: "response"
      }

      assert Webhook.execute(action, context) == nil

      Oban.drain_queue(queue: :gpt_webhook_queue)

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
      assert log != nil
      assert log.error != nil
    end
  end

  # ---------------------------------------------------------------------------
  # await_flow_message helpers (copied verbatim from spec)
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
end
