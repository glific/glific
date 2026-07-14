defmodule Glific.Flows.Webhooks.VoiceFilesearchGpt do
  @moduledoc """
  Async webhook implementation for the `voice-filesearch-gpt` flow node.

  Runs inside the `Glific.Flows.Webhook` Oban worker (worker phase): it transcribes the
  incoming audio synchronously with Gemini speech-to-text, then fires the async Kaapi LLM
  request with a voice callback path so the answer is post-processed (NMT + TTS) before
  resuming the flow.

  The Kaapi response arrives at `GlificWeb.Flows.FlowResumeController.voice_flow_resume/2`
  and is post-processed here by `voice_post_process/3` (NMT + TTS) before
  `Glific.Flows.Webhook` resumes the flow. The Gemini STT / NMT+TTS calls live here directly
  (the standalone `*_with_bhasini` webhook nodes have been removed).
  """

  use Glific.Flows.Webhooks.Async, name: "voice-filesearch-gpt"

  alias Glific.Flows.Webhooks.Behaviour
  alias Glific.Flows.Webhooks.ErrorType
  alias Glific.Flows.Webhooks.Instrumentation
  alias Glific.Flows.Webhooks.Kaapi, as: KaapiWebhook
  alias Glific.OpenAI.ChatGPT
  alias Glific.Partners
  alias Glific.ThirdParty.Gemini
  alias Glific.ThirdParty.Kaapi

  @doc """
  Fires the voice LLM pipeline: synchronous Gemini STT, then the async Kaapi LLM call.
  Returns the Kaapi ack map, or a failure map if STT fails or Kaapi is not configured.
  """
  @impl true
  @spec call(map(), Behaviour.ctx()) :: map()
  def call(fields, _ctx) do
    # Check Kaapi creds before running STT — no point transcribing if the LLM call can't
    # be made. The STT step itself uses Gemini, not the Kaapi API key.
    with {:ok, {organization_id, flow_id, contact_id}} <- KaapiWebhook.parse_flow_fields(fields),
         {:ok, %{"api_key" => api_key}} when is_binary(api_key) <-
           Kaapi.fetch_kaapi_creds(organization_id) do
      run_voice_pipeline(fields, organization_id, flow_id, contact_id, api_key)
    else
      {:error, error_type, reason} when is_atom(error_type) ->
        %{success: false, reason: reason, error_type: error_type}

      {:error, reason} when is_binary(reason) ->
        %{success: false, reason: reason, error_type: :unknown}

      _ ->
        %{success: false, reason: "Kaapi is not active", error_type: :unknown}
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
    voice_start_timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    case transcribe(fields["speech"], organization_id) do
      {:ok, transcribed_text} ->
        fields
        |> Map.put("question", transcribed_text)
        |> dispatch_llm(organization_id, flow_id, contact_id, api_key, voice_start_timestamp)

      {:error, error_type, reason} ->
        %{success: false, reason: reason, error_type: error_type}

      {:error, reason} ->
        %{success: false, reason: reason, error_type: :unknown}
    end
  end

  # Synchronous Gemini speech-to-text. Validates the audio URL, then transcribes; a
  # failure short-circuits the pipeline so the async webhook surfaces it on the Failure branch.
  @spec transcribe(any(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, ErrorType.t(), String.t()} | {:error, String.t()}
  defp transcribe(speech, organization_id) do
    with :ok <- KaapiWebhook.validate_media(speech) do
      case Gemini.speech_to_text(speech, organization_id) do
        %{success: true, asr_response_text: transcribed_text} ->
          {:ok, transcribed_text}

        %{success: false} = failure ->
          {:error, to_string(failure[:asr_response_text] || "Speech to text failed")}
      end
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
      KaapiWebhook.build_flow_resume_metadata(
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

    KaapiWebhook.call_llm(fields, [{"X-API-KEY", api_key}], callback_url, request_metadata)
  end

  @doc """
  Voice resume post-processing: applies NMT + TTS to the Kaapi LLM `response`
  (translate + generate audio), merging `translated_text` and `media_url` into the
  response for the voice reply.

  Called by `Glific.Flows.Webhook` on the `/kaapi/voice_flow_resume` callback path
  only when the callback succeeded — there's nothing to speak on a failure.
  """
  @spec voice_post_process(non_neg_integer(), map()) :: map()
  def voice_post_process(organization_id, response) do
    llm_response_text = response["message"] || ""
    voice_fields = response["voice_post_process"] || %{}

    {translated_text, media_url} =
      nmt_tts(organization_id, llm_response_text, voice_fields)

    response
    |> Map.put("translated_text", translated_text)
    |> Map.put("media_url", media_url)
  end

  # Non-empty text: translate (when needed) + synthesise audio via Gemini directly. A
  # successful Gemini result carries `translated_text` / `media_url`; any failure falls back
  # to the untranslated LLM text with no audio.
  @spec nmt_tts(non_neg_integer(), String.t(), map()) :: {String.t(), String.t() | nil}
  defp nmt_tts(organization_id, text, voice_fields) when text != "" do
    source_language = normalize_language(voice_fields["source_language"])
    target_language = normalize_language(voice_fields["target_language"])
    speech_engine = voice_fields["speech_engine"] || ""

    result =
      if source_language == target_language do
        tts_only(source_language, organization_id, text, speech_engine)
      else
        nmt_tts_call(source_language, target_language, organization_id, text,
          speech_engine: speech_engine
        )
      end

    case result do
      %{success: true} = success -> {success[:translated_text] || text, success[:media_url]}
      _ -> {text, nil}
    end
  end

  # Kaapi reported success but gave us no text to speak: report and resume with no audio.
  defp nmt_tts(organization_id, _text, _voice_fields) do
    report_empty_message(organization_id)
    {"", nil}
  end

  @spec normalize_language(String.t() | nil) :: String.t()
  defp normalize_language(nil), do: ""
  defp normalize_language(language), do: String.downcase(language)

  # Source and target match: plain TTS. OpenAI for English / explicit open_ai engine,
  # Gemini otherwise.
  @spec tts_only(String.t(), non_neg_integer(), String.t(), String.t()) :: map()
  defp tts_only(language, organization_id, text, speech_engine) do
    if speech_engine == "open_ai" || language == "english" do
      ChatGPT.text_to_speech_with_open_ai(organization_id, text)
    else
      Glific.Metrics.increment("Gemini NMT TTS Call", organization_id)
      Gemini.text_to_speech(organization_id, text)
    end
  end

  # Source and target differ: translate + synthesise via Gemini, guarded by a GCS-enabled +
  # supported-language pre-check (so a disabled/unsupported org fails fast without a network call).
  @spec nmt_tts_call(String.t(), String.t(), non_neg_integer(), String.t(), Keyword.t()) :: map()
  defp nmt_tts_call(source_language, target_language, organization_id, text, opts) do
    organization = Partners.organization(organization_id)
    services = organization.services["google_cloud_storage"]

    with false <- is_nil(services),
         true <- Gemini.valid_language?(source_language, target_language) do
      Glific.Metrics.increment("Gemini NMT TTS Call", organization_id)
      Gemini.nmt_text_to_speech(organization_id, text, source_language, target_language, opts)
    else
      true ->
        %{success: false, reason: "GCS is disabled"}

      false ->
        %{success: false, reason: "Language not supported in Gemini"}
    end
  end

  # success=true but empty body — the HTTP call succeeded (status 200), the content
  # was just unusable. Reporting (SystemError + flow_webhooks namespace) is owned by
  # the centralised Instrumentation module, like every other webhook failure.
  @spec report_empty_message(non_neg_integer()) :: :ok
  defp report_empty_message(organization_id) do
    Instrumentation.report_failure(name(), %{
      organization_id: organization_id,
      http_status: 200,
      reason: "Kaapi callback returned success=true but message was empty/nil"
    })
  end
end
