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

  import Glific.WebhookTestHelpers

  alias Glific.{
    Fixtures,
    Flows.Action,
    Flows.Flow,
    Flows.FlowContext,
    Flows.Webhook,
    Flows.Webhooks.TextToSpeech,
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

    # The STT/TTS rate-limit ExRated bucket is process-global and shared across both webhooks.
    # Reset it before every test so tokens don't leak between tests (order-dependent snoozes).
    ExRated.delete_bucket("kaapi_stt_tts:#{Partners.organization(1).shortcode}")
    :ok
  end

  # ---------------------------------------------------------------------------
  # Helpers — TTS-specific callback format
  # ---------------------------------------------------------------------------

  defp build_callback_params(
         organization_id,
         flow_id,
         contact_id,
         webhook_log_id,
         success,
         message
       ) do
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

    test "timeout - outbound Kaapi TTS request times out, flow routes to failure branch", %{
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
        headers: %{"Accept" => "application/json"},
        method: "FUNCTION",
        url: "text_to_speech",
        body: Jason.encode!(%{text: "Hello world"})
      }

      assert Webhook.execute(action, context) == nil
      assert_enqueued(worker: Webhook, prefix: "global")
      Oban.drain_queue(queue: :gpt_webhook_queue)

      # NOTE: The Oban worker routes to the failure branch because action.result_name
      # is nil in the %Action{} struct (no result_name set). Since result_name is nil,
      # handle/3 routes to the FAILURE branch via FlowContext.wakeup_one with a
      # "Failure" temp message.
      message = await_flow_message(contact.id, "failure")
      assert message.body == "failure"

      log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_filter}))
      assert log != nil
      assert log.error != nil
    end
  end

  # Dispatch-level tests: exercise call/2 (Kaapi ack + payload structure) directly. The per-org
  # STT/TTS rate-limit bucket is reset per test so these extra call/2 invocations don't exhaust
  # the shared budget and snooze.
  describe "text_to_speech dispatch" do
    setup do
      %{fields: tts_fields(Fixtures.contact_fixture().id)}
    end

    test "returns success when Kaapi acknowledges the TTS request", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :post} -> %Tesla.Env{status: 200, body: %{request_id: "req_456"}}
      end)

      assert TextToSpeech.call(fields, %{}).success == true
    end

    test "sends correct payload structure to Kaapi for TTS", %{fields: fields} do
      Tesla.Mock.mock(fn
        %{method: :post, body: body} ->
          decoded = Jason.decode!(body)
          assert get_in(decoded, ["query", "input"]) == "Hello world"
          assert get_in(decoded, ["config", "blob", "completion", "type"]) == "tts"
          assert get_in(decoded, ["config", "blob", "completion", "provider"]) == "google"

          assert get_in(decoded, ["config", "blob", "completion", "params", "model"]) ==
                   "gemini-3.1-flash-tts-preview"

          assert get_in(decoded, ["config", "blob", "completion", "params", "voice"]) == "Kore"

          assert get_in(decoded, ["config", "blob", "completion", "params", "language"]) ==
                   "hindi"

          metadata = decoded["request_metadata"]
          assert metadata["organization_id"] == 1
          assert metadata["flow_id"] == 1
          assert metadata["webhook_log_id"] == 1
          assert metadata["result_name"] == "response"
          assert decoded["callback_url"] =~ "/webhook/flow_resume"

          %Tesla.Env{status: 200, body: %{"job_id" => "tts-456"}}
      end)

      assert TextToSpeech.call(fields, %{}).success == true
    end
  end

  defp tts_fields(contact_id) do
    %{
      "text" => "Hello world",
      "organization_id" => "1",
      "flow_id" => "1",
      "contact_id" => "#{contact_id}",
      "webhook_log_id" => 1,
      "result_name" => "response"
    }
  end

  describe "perform/1 rate limiting" do
    test "snoozes a text_to_speech job once the shared per-org rate limit is exceeded" do
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
          "url" => "text_to_speech",
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
