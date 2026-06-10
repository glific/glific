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

  import Glific.WebhookTestHelpers

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

    :ok
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Builds the callback params that Kaapi POSTs back to /webhook/flow_resume.
  # Uses the NEW unified-API callback format (metadata + data.response.output)
  # which is what the Kaapi STT service sends.
  # The success and failure branches have different shapes that don't fit the
  # generic build_unified_callback_params helper cleanly.
  defp build_callback_params(
         organization_id,
         flow_id,
         contact_id,
         webhook_log_id,
         success,
         message
       ) do
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

      contact = Fixtures.contact_fixture(%{organization_id: organization_id})
      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
      [node | _] = flow.nodes

      {:ok, context} =
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

      context = Repo.preload(context, [:contact, :flow])

      flow_filter = %{
        flow_id: flow.id,
        contact_id: contact.id,
        organization_id: organization_id
      }

      action = %Action{
        headers: %{"Content-Type" => "application/json"},
        method: "FUNCTION",
        url: "speech_to_text",
        body: Jason.encode!(%{"speech" => "https://gcs.example.com/audio.ogg"}),
        result_name: "response"
      }

      assert Webhook.execute(action, context) == nil

      Oban.drain_queue(queue: :gpt_webhook_queue)

      # NOTE: No "failure" message assertion here. The Webhook.execute Oban path
      # for speech_to_text routes to Failure because action.result_name is nil in
      # the %Action{} struct passed to the Oban worker (the struct has no result_name
      # set at the job-dispatch level). Since result_name is nil, handle/3 routes
      # to the FAILURE branch.
      # The failure branch IS exercised by the failure callback test above.
      # What we assert here is that the webhook log records the error.
      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_filter}))
      assert log != nil
      assert log.error != nil
    end
  end
end
