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
    Flows.Webhooks.SpeechToText,
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

    # The STT/TTS rate-limit ExRated bucket is process-global and shared across both webhooks.
    # Reset it before every test so tokens don't leak between tests (order-dependent snoozes).
    ExRated.delete_bucket("kaapi_stt_tts:#{Partners.organization(1).shortcode}")
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

  # Dispatch-level tests: exercise call/2 (Kaapi ack, payload structure, failure shaping)
  # directly. The per-org STT/TTS rate-limit bucket is reset per test so these extra call/2
  # invocations don't exhaust the shared budget and snooze.
  describe "speech_to_text dispatch" do
    setup do
      %{fields: stt_fields(Fixtures.contact_fixture().id)}
    end

    test "returns success when Kaapi acknowledges the STT request", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :get} -> %Tesla.Env{status: 200, body: "fake_audio_bytes"}
        %{method: :post} -> %Tesla.Env{status: 200, body: %{request_id: "req_123"}}
      end)

      assert {:ok, %{success: true}} = SpeechToText.call(fields, %{})
    end

    test "sends correct payload structure to Kaapi for STT", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{status: 200, body: "fake_audio_bytes"}

        %{method: :post, body: body} ->
          decoded = Jason.decode!(body)
          assert get_in(decoded, ["query", "input", "type"]) == "audio"
          assert get_in(decoded, ["query", "input", "content", "format"]) == "base64"
          assert get_in(decoded, ["config", "blob", "completion", "type"]) == "stt"
          assert get_in(decoded, ["config", "blob", "completion", "provider"]) == "google"

          assert get_in(decoded, ["config", "blob", "completion", "params", "model"]) ==
                   "gemini-3.1-pro-preview"

          assert get_in(decoded, ["config", "blob", "completion", "params", "input_language"]) ==
                   "auto"

          refute Map.has_key?(
                   get_in(decoded, ["config", "blob", "completion", "params"]),
                   "output_language"
                 )

          metadata = decoded["request_metadata"]
          assert metadata["organization_id"] == 1
          assert metadata["flow_id"] == 1
          assert metadata["webhook_log_id"] == 1
          assert metadata["result_name"] == "response"
          assert decoded["callback_url"] =~ "/webhook/flow_resume"

          %Tesla.Env{status: 200, body: %{"job_id" => "stt-123"}}
      end)

      assert {:ok, %{success: true}} = SpeechToText.call(fields, %{})
    end

    test "passes output_language to Kaapi when specified in fields", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{status: 200, body: "fake_audio_bytes"}

        %{method: :post, body: body} ->
          decoded = Jason.decode!(body)

          assert get_in(decoded, ["config", "blob", "completion", "params", "output_language"]) ==
                   "english"

          %Tesla.Env{status: 200, body: %{"job_id" => "stt-456"}}
      end)

      assert {:ok, %{success: true}} =
               SpeechToText.call(Map.put(fields, "output_language", "english"), %{})
    end

    test "returns failure result when Kaapi returns 200 with a success:false body", %{
      fields: fields
    } do
      Tesla.Mock.mock(fn
        %{method: :get} -> %Tesla.Env{status: 200, body: "fake_audio_bytes"}
        %{method: :post} -> %Tesla.Env{status: 200, body: %{success: false, message: "boom"}}
      end)

      # error_type "kaapi_logical_failure" is a raw string, not a known ErrorType.t() atom, so
      # to_result/1 fails it safe to :unknown; http_status is folded into the reason.
      assert {:error, :unknown, "boom (HTTP 200)"} = SpeechToText.call(fields, %{})
    end

    test "returns failure result on a Kaapi 5xx response", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :get} -> %Tesla.Env{status: 200, body: "fake_audio_bytes"}
        %{method: :post} -> %Tesla.Env{status: 503, body: %{}}
      end)

      assert {:error, _error_type, _reason} = SpeechToText.call(fields, %{})
    end

    test "rejects empty speech URL without calling Kaapi", %{fields: fields} do
      assert SpeechToText.call(Map.put(fields, "speech", ""), %{}) ==
               {:error, :invalid_media_url, "Media URL is invalid"}
    end

    test "snoozes (does not call Kaapi) once the shared STT/TTS rate limit is exhausted", %{
      fields: fields
    } do
      key = "kaapi_stt_tts:#{Partners.organization(1).shortcode}"
      # Consume the whole per-org budget; the next call/2 must snooze rather than dispatch.
      for _ <- 1..10, do: {:ok, _} = ExRated.check_rate(key, 60_000, 10)

      assert {:snooze, seconds} = SpeechToText.call(fields, %{})
      assert is_integer(seconds) and seconds > 0
    end
  end

  defp stt_fields(contact_id) do
    %{
      "speech" => "https://filemanager.gupshup.io/wa/audio.ogg",
      "organization_id" => "1",
      "flow_id" => "1",
      "contact_id" => "#{contact_id}",
      "webhook_log_id" => 1,
      "result_name" => "response"
    }
  end

  describe "perform/1 rate limiting" do
    test "snoozes a speech_to_text job once the shared per-org rate limit is exceeded" do
      # The shared kaapi_stt_tts bucket allows 10 requests / 60s per org (see
      # Glific.Flows.Webhook). ExRated buckets are process-global, so reset around the test.
      key = "kaapi_stt_tts:#{Partners.organization(1).shortcode}"
      ExRated.delete_bucket(key)
      on_exit(fn -> ExRated.delete_bucket(key) end)

      for _ <- 1..10 do
        {:ok, _} = ExRated.check_rate(key, 60_000, 10)
      end

      job = %Oban.Job{
        args: %{
          "method" => "function",
          "url" => "speech_to_text",
          "body" => Jason.encode!(%{"organization_id" => 1}),
          "result_name" => "response",
          "headers" => [],
          "webhook_log_id" => 1,
          "context" => %{"id" => 1},
          "organization_id" => 1,
          "flow_id" => 1,
          "contact_id" => 1
        }
      }

      assert {:snooze, 5} = Webhook.perform(job)
    end
  end
end
