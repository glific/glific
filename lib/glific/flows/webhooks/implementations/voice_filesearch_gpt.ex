defmodule Glific.Flows.Webhooks.VoiceFilesearchGpt do
  @moduledoc """
  Async webhook implementation for the `voice-filesearch-gpt` flow node.

  Runs inside the `Glific.Flows.Webhook` Oban worker (worker phase): it transcribes the
  incoming audio synchronously (Bhasini STT, via the still-`CommonWebhook`
  `speech_to_text_with_bhasini` webhook), then fires the async Kaapi LLM request with a
  voice callback path so the answer is post-processed (NMT + TTS) before resuming the flow.

  The Kaapi response arrives at `GlificWeb.Flows.FlowResumeController.voice_flow_resume/2`,
  which runs `handle_resume/2` (voice post-processing) before resuming.
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
    {:ok, org_id} = fields["organization_id"] |> Glific.parse_maybe_integer()
    stt_fields = Map.put(fields, "contact", %{"id" => fields["contact_id"]})
    voice_start_timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    Glific.Metrics.increment("Voice Unified LLM Call", org_id)

    case CommonWebhook.webhook("speech_to_text_with_bhasini", stt_fields) do
      %{success: true, asr_response_text: transcribed_text} ->
        updated_fields = Map.put(fields, "question", transcribed_text)
        dispatch_llm(updated_fields, voice_start_timestamp)

      %{success: false} = stt_failure ->
        %{success: false, reason: stt_failure[:asr_response_text] || "Speech to text failed"}

      {:error, reason} ->
        %{success: false, reason: inspect(reason)}
    end
  end

  @spec dispatch_llm(map(), integer()) :: map()
  defp dispatch_llm(fields, voice_start_timestamp) do
    {organization_id, flow_id, contact_id} = KaapiSupport.parse_flow_fields(fields)

    case Kaapi.fetch_kaapi_creds(organization_id) do
      {:ok, %{"api_key" => api_key}} when is_binary(api_key) ->
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

      _ ->
        %{success: false, reason: "Kaapi is not active"}
    end
  end

  @doc """
  Voice callback handler. Applies NMT + TTS (`CommonWebhook.voice_post_process/3`) to the
  parsed Kaapi LLM `response`, producing `translated_text` + `media_url` for the voice reply.
  `ctx` carries `organization_id` and `success` (the raw callback success flag).
  """
  @impl true
  @spec handle_resume(map(), Behaviour.ctx()) :: {:ok | :error, map()}
  def handle_resume(response, ctx) do
    organization_id = Map.get(ctx, :organization_id)
    success = Map.get(ctx, :success)
    voice_response = CommonWebhook.voice_post_process(organization_id, success, response)
    {:ok, voice_response}
  end
end
