defmodule Glific.Flows.Webhooks.VoiceFilesearchGpt do
  @moduledoc """
  Async webhook implementation for the `voice-filesearch-gpt` flow node.

  Runs inside the `Glific.Flows.Webhook` Oban worker (worker phase): it transcribes the
  incoming audio synchronously (Bhasini STT, via the still-`CommonWebhook`
  `speech_to_text_with_bhasini` webhook), then fires the async Kaapi LLM request with a
  voice callback path so the answer is post-processed (NMT + TTS) before resuming the flow.

  The Kaapi response arrives at `GlificWeb.Flows.FlowResumeController.voice_flow_resume/2`
  and is post-processed (NMT + TTS via `CommonWebhook.voice_post_process/3`) by
  `Glific.Flows.Webhook` before resuming.
  """

  use Glific.Flows.Webhooks.Async, name: "voice-filesearch-gpt"

  alias Glific.Clients.CommonWebhook
  alias Glific.Flows.Webhooks.Behaviour
  alias Glific.Flows.Webhooks.Kaapi, as: KaapiSupport
  alias Glific.ThirdParty.Kaapi

  @doc """
  Fires the voice LLM pipeline: synchronous Bhasini STT, then the async Kaapi LLM call.
  Returns the Kaapi ack map, or a failure map if STT fails or Kaapi is not configured.
  """
  @impl true
  @spec call(map(), Behaviour.ctx()) :: map()
  def call(fields, _ctx) do
    # Check Kaapi creds before running STT — no point transcribing if the LLM call can't
    # be made. The Bhasini STT step itself uses Gemini/Bhasini, not the Kaapi API key.
    with {:ok, {organization_id, flow_id, contact_id}} <- KaapiSupport.parse_flow_fields(fields),
         {:ok, %{"api_key" => api_key}} when is_binary(api_key) <-
           Kaapi.fetch_kaapi_creds(organization_id) do
      run_voice_pipeline(fields, organization_id, flow_id, contact_id, api_key)
    else
      {:error, reason} when is_binary(reason) -> %{success: false, reason: reason}
      _ -> %{success: false, reason: "Kaapi is not active"}
    end
  end

  @spec run_voice_pipeline(
          map(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          String.t()
        ) :: map()
  defp run_voice_pipeline(fields, organization_id, flow_id, contact_id, api_key) do
    stt_fields = Map.put(fields, "contact", %{"id" => fields["contact_id"]})
    voice_start_timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    Glific.Metrics.increment("Voice Unified LLM Call", organization_id)

    case CommonWebhook.webhook("speech_to_text_with_bhasini", stt_fields) do
      %{success: true, asr_response_text: transcribed_text} ->
        fields
        |> Map.put("question", transcribed_text)
        |> dispatch_llm(organization_id, flow_id, contact_id, api_key, voice_start_timestamp)

      %{success: false} = stt_failure ->
        %{success: false, reason: stt_failure[:asr_response_text] || "Speech to text failed"}

      # The public speech_to_text_with_bhasini webhook normalizes failures to a bare
      # string (the FUNCTION-webhook Failure contract), so handle that shape too.
      reason when is_binary(reason) ->
        %{success: false, reason: reason}

      other ->
        %{success: false, reason: inspect(other)}
    end
  end

  @spec dispatch_llm(
          map(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          String.t(),
          integer()
        ) :: map()
  defp dispatch_llm(fields, organization_id, flow_id, contact_id, api_key, voice_start_timestamp) do
    {callback_url, request_metadata} =
      KaapiSupport.build_flow_resume_metadata(
        organization_id,
        flow_id,
        contact_id,
        fields,
        "/kaapi/voice_flow_resume",
        voice_start_timestamp
      )

    request_metadata =
      Map.merge(request_metadata, %{
        call_type: "voice_llm",
        webhook_name: name(),
        voice_post_process: %{
          source_language: fields["source_language"],
          target_language: fields["target_language"],
          speech_engine: fields["speech_engine"] || ""
        }
      })

    KaapiSupport.call_llm(fields, [{"X-API-KEY", api_key}], callback_url, request_metadata)
  end
end
