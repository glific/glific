defmodule Glific.Flows.WebhookPerformTest do
  @moduledoc """
  Focused tests for `Glific.Flows.Webhook.perform/1`'s rate-limit gate (lifted from the
  former SttTtsWorker). async: false because ExRated buckets are process-global.
  """
  use Glific.DataCase, async: false

  alias Glific.Flows.Webhook
  alias Glific.Partners

  @rate_limit_max 10
  @rate_limit_window_ms 60_000

  defp stt_job(org_id) do
    %Oban.Job{
      args: %{
        "method" => "function",
        "url" => "speech_to_text",
        # organization_id must live in the body: the STT module reads it from the webhook
        # fields (via parse_flow_fields) before enforcing the shared rate limit.
        "body" => Jason.encode!(%{"organization_id" => org_id}),
        "result_name" => "response",
        "headers" => [],
        "webhook_log_id" => 1,
        "context" => %{"id" => 1},
        "organization_id" => org_id,
        "flow_id" => 1,
        "contact_id" => 1
      }
    }
  end

  describe "perform/1 rate limiting" do
    test "snoozes a speech_to_text job once the per-org rate limit is exceeded", %{
      organization_id: org_id
    } do
      key = "kaapi_stt_tts:#{Partners.organization(org_id).shortcode}"
      # ExRated buckets are process-global, so reset before and after to avoid leaking the
      # exhausted bucket into other suites that dispatch STT/TTS for this org.
      ExRated.delete_bucket(key)
      on_exit(fn -> ExRated.delete_bucket(key) end)

      # Consume the whole per-org budget for the window.
      for _ <- 1..@rate_limit_max do
        {:ok, _} = ExRated.check_rate(key, @rate_limit_window_ms, @rate_limit_max)
      end

      # The next STT job must snooze rather than dispatch to Kaapi.
      assert {:snooze, 5} = Webhook.perform(stt_job(org_id))
    end
  end
end
