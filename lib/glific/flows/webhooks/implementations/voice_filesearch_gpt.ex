defmodule Glific.Flows.Webhooks.VoiceFilesearchGpt do
  @moduledoc """
  Async webhook implementation for the `voice-filesearch-gpt` flow node: transcribes the
  incoming audio with Gemini STT, then fires the async Kaapi LLM request with a voice callback
  path so the answer is post-processed (NMT + TTS) before resuming the flow.
  """

  use Glific.Flows.Webhooks.Async, name: "voice-filesearch-gpt"

  alias Glific.Flows.Webhooks.Behaviour
  alias Glific.Flows.Webhooks.ErrorReporter
  alias Glific.Flows.Webhooks.ErrorType
  alias Glific.Flows.Webhooks.Instrumentation
  alias Glific.Flows.Webhooks.Kaapi, as: KaapiWebhook
  alias Glific.OpenAI.ChatGPT
  alias Glific.Partners
  alias Glific.SafeLog
  alias Glific.ThirdParty.Gemini
  alias Glific.ThirdParty.Kaapi

  @doc """
  Fires the voice LLM pipeline: synchronous Gemini STT, then the async Kaapi LLM call.
  """
  @impl true
  @spec call(map(), Behaviour.ctx()) :: Behaviour.result()
  def call(fields, _ctx) do
    with {:ok, {organization_id, flow_id, contact_id}} <- KaapiWebhook.parse_flow_fields(fields),
         {:ok, %{"api_key" => api_key}} when is_binary(api_key) <-
           Kaapi.fetch_kaapi_creds(organization_id) do
      run_voice_pipeline(fields, organization_id, flow_id, contact_id, api_key)
    else
      {:error, _error_type, _reason} = error ->
        error

      # unconfigured org (fetch_kaapi_creds -> {:error, binary}): a provisioning gap -> system
      {:error, reason} when is_binary(reason) ->
        {:error, :missing_api_key, reason}

      _ ->
        {:error, :unknown, "Unexpected Kaapi dispatch failure"}
    end
  end

  @spec run_voice_pipeline(
          map(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          String.t()
        ) :: Behaviour.result()
  defp run_voice_pipeline(fields, organization_id, flow_id, contact_id, api_key) do
    voice_start_timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    case transcribe(fields["speech"], organization_id) do
      {:ok, transcribed_text} ->
        fields
        |> Map.put("question", transcribed_text)
        |> dispatch_llm(organization_id, flow_id, contact_id, api_key, voice_start_timestamp)
        |> KaapiWebhook.to_result()

      {:error, _error_type, _reason} = error ->
        error
    end
  end

  @spec transcribe(any(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, ErrorType.t(), String.t()}
  defp transcribe(speech, organization_id) do
    with :ok <- KaapiWebhook.validate_media(speech) do
      case Gemini.speech_to_text(speech, organization_id) do
        %{success: true, asr_response_text: transcribed_text} when is_binary(transcribed_text) ->
          {:ok, transcribed_text}

        %{success: false} = failure ->
          detail = failure[:asr_response_text]
          {:error, KaapiWebhook.from_http_status(detail), stt_failure_reason(detail)}

        # catch-all: normalise an unusual passthrough instead of raising CaseClauseError
        unexpected ->
          {:error, :unknown, stt_failure_reason(unexpected)}
      end
    end
  end

  # to_string/1 raises on a map; safe_inspect renders any shape
  @spec stt_failure_reason(any()) :: String.t()
  defp stt_failure_reason(detail) when is_binary(detail), do: detail
  defp stt_failure_reason(detail), do: "Speech to text failed (#{SafeLog.safe_inspect(detail)})"

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
        "/webhook/flow_resume",
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
  Callback phase: overrides the async default (pass-through) to add NMT + TTS post-processing,
  but only on success — a failure has nothing to speak.
  """
  @impl true
  @spec handle_callback(map(), map(), Behaviour.ctx()) :: map()
  def handle_callback(%{"success" => true}, response, %{organization_id: organization_id}) do
    voice_post_process(organization_id, response)
  end

  def handle_callback(_result, response, _ctx), do: response

  @doc """
  Voice resume post-processing: applies NMT + TTS to the Kaapi LLM `response`, merging
  `translated_text` and `media_url` into it for the voice reply.
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
      %{success: true} = success ->
        {success[:translated_text] || text, success[:media_url]}

      failure ->
        report_tts_failure(organization_id, failure)
        {text, nil}
    end
  end

  defp nmt_tts(organization_id, _text, _voice_fields) do
    report_empty_message(organization_id)
    {"", nil}
  end

  @spec normalize_language(String.t() | nil) :: String.t()
  defp normalize_language(nil), do: ""
  defp normalize_language(language), do: String.downcase(language)

  @spec tts_only(String.t(), non_neg_integer(), String.t(), String.t()) :: map()
  defp tts_only(language, organization_id, text, speech_engine) do
    if speech_engine == "open_ai" || language == "english" do
      ChatGPT.text_to_speech_with_open_ai(organization_id, text)
    else
      Gemini.text_to_speech(organization_id, text)
    end
  end

  # GCS-enabled + supported-language pre-check so an unsupported org fails fast without a network call
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
        %{success: false, reason: "GCS is disabled", error_type: :invalid_input}

      false ->
        %{success: false, reason: "Language not supported in Gemini", error_type: :invalid_input}
    end
  end

  @spec report_empty_message(non_neg_integer()) :: :ok
  defp report_empty_message(organization_id) do
    Instrumentation.report_failure(name(), %{
      organization_id: organization_id,
      http_status: 200,
      reason: "Kaapi callback returned success=true but message was empty/nil"
    })
  end

  # Reported for visibility; the caller still degrades to text-only so the flow resumes.
  @spec report_tts_failure(non_neg_integer(), map()) :: :ok
  defp report_tts_failure(organization_id, failure) do
    reason = failure[:reason] || failure[:error] || "Voice TTS post-processing failed"
    reason = if is_binary(reason), do: reason, else: SafeLog.safe_inspect(reason)

    ErrorReporter.report(tts_error_type(failure), reason, %{
      organization_id: organization_id,
      webhook_name: name()
    })
  end

  @spec tts_error_type(map()) :: ErrorType.t()
  defp tts_error_type(%{error_type: error_type})
       when is_atom(error_type) and not is_nil(error_type),
       do: error_type

  defp tts_error_type(%{http_status: status}) when is_integer(status),
    do: KaapiWebhook.from_http_status(status)

  defp tts_error_type(%{reason: reason}) when is_binary(reason) do
    if reason =~ ~r/GCS is disabled|Language not supported/i, do: :invalid_input, else: :unknown
  end

  defp tts_error_type(_failure), do: :unknown
end
