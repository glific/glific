defmodule Glific.Clients.CommonWebhook do
  @moduledoc """
  Common webhooks which we can call with any clients.
  """

  alias Glific.ASR.Bhasini
  alias Glific.Assistants.Assistant
  alias Glific.Flows.Webhook
  alias Glific.Flows.Webhook.SystemError
  alias Glific.Flows.Webhooks.Dispatcher
  alias Glific.OpenAI.ChatGPT
  alias Glific.Partners
  alias Glific.Providers.Gupshup.ApiClient, as: GupshupClient
  alias Glific.Repo
  alias Glific.ThirdParty.Gemini
  alias Glific.ThirdParty.Kaapi
  alias Glific.ThirdParty.Kaapi.ApiClient

  require Logger

  @doc """
  Create a webhook with different signatures along with header, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map(), list()) :: map() | String.t()
  def webhook("call_and_wait", fields, headers) do
    {:ok, organization_id} = fields["organization_id"] |> Glific.parse_maybe_integer()
    result_name = fields["result_name"]
    webhook_log_id = fields["webhook_log_id"]
    {:ok, flow_id} = fields["flow_id"] |> Glific.parse_maybe_integer()
    {:ok, contact_id} = fields["contact_id"] |> Glific.parse_maybe_integer()
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
        signature_payload["timestamp"]
      )

    organization = Partners.organization(organization_id)

    callback_url =
      Glific.api_callback_base(organization.shortcode) <>
        "/webhook/flow_resume"

    payload =
      fields
      |> Map.merge(signature_payload)
      |> Map.put("signature", signature)
      |> Map.put("callback_url", callback_url)
      |> Map.put("webhook_log_id", webhook_log_id)
      |> Map.put("result_name", result_name)
      |> maybe_put_response_id(fields)

    case Enum.find(headers, fn {key, _v} -> key == "X-API-KEY" end) do
      {_, org_api_key} ->
        call_responses_and_format(payload, org_api_key)

      _ ->
        # returns a bare-string failure that routes the flow to the Failure category,
        # not logging any failure to appsignal because the function is set for deprecation
        "Missing Kaapi API key"
    end
  end

  def webhook("unified-llm-call", fields, headers) do
    {organization_id, flow_id, contact_id} = parse_flow_fields(fields)

    {callback_url, request_metadata} =
      build_flow_resume_metadata(organization_id, flow_id, contact_id, fields)

    request_metadata =
      Map.merge(request_metadata, %{call_type: "llm", webhook_name: "unified-llm-call"})

    with_failure_reporting("unified-llm-call", organization_id, fn ->
      do_unified_llm_call(fields, headers, callback_url, request_metadata)
    end)
  end

  # Does synchronous STT (via Bhasini/Gemini) then calls the unified LLM with a voice
  # callback path so the response is post-processed (NMT+TTS) before resuming the flow.
  def webhook("unified-voice-llm-call", fields, headers) do
    {:ok, org_id} = fields["organization_id"] |> Glific.parse_maybe_integer()
    stt_fields = Map.put(fields, "contact", %{"id" => fields["contact_id"]})
    voice_start_timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    Glific.Metrics.increment("Voice Unified LLM Call", org_id)

    case do_speech_to_text_with_bhasini(stt_fields) do
      %{success: true, asr_response_text: transcribed_text} ->
        updated_fields = Map.put(fields, "question", transcribed_text)
        {organization_id, flow_id, contact_id} = parse_flow_fields(fields)

        {callback_url, request_metadata} =
          build_flow_resume_metadata(
            organization_id,
            flow_id,
            contact_id,
            updated_fields,
            "/kaapi/voice_flow_resume",
            voice_start_timestamp
          )

        request_metadata =
          Map.merge(request_metadata, %{
            call_type: "voice_llm",
            webhook_name: "unified-voice-llm-call",
            voice_post_process: %{
              source_language: fields["source_language"],
              target_language: fields["target_language"],
              speech_engine: fields["speech_engine"] || ""
            }
          })

        with_failure_reporting("unified-voice-llm-call", organization_id, fn ->
          do_unified_llm_call(updated_fields, headers, callback_url, request_metadata)
        end)

      %{success: false} = stt_failure ->
        %{success: false, reason: stt_failure[:asr_response_text] || "Speech to text failed"}

      {:error, reason} ->
        %{success: false, reason: inspect(reason)}
    end
  end

  # Generic Kaapi STT webhook (async — result delivered via flow_resume callback).
  # Optional fields from flow node: provider, model, language (input language for transcription),
  # output_language (if omitted, Kaapi transcribes in the input language without translation)
  def webhook("speech_to_text", fields, _headers) do
    speech = fields["speech"]
    {organization_id, flow_id, contact_id} = parse_flow_fields(fields)

    {callback_url, request_metadata} =
      build_flow_resume_metadata(organization_id, flow_id, contact_id, fields)

    request_metadata =
      Map.merge(request_metadata, %{call_type: "stt", webhook_name: "speech_to_text"})

    stt_opts = %{
      provider: fields["provider"],
      model: fields["model"],
      language: fields["language"],
      output_language: fields["output_language"]
    }

    with_failure_reporting("speech_to_text", organization_id, fn ->
      case validate_params(fields) do
        :ok ->
          Glific.Metrics.increment("Kaapi STT Call", organization_id)
          Kaapi.speech_to_text(speech, callback_url, request_metadata, organization_id, stt_opts)

        {:error, reason} ->
          %{success: false, reason: reason}
      end
    end)
  end

  # Generic Kaapi TTS webhook (async — result delivered via flow_resume callback).
  # Optional fields from flow node: provider, model, language, voice
  def webhook("text_to_speech", fields, _headers) do
    text = fields["text"]
    {organization_id, flow_id, contact_id} = parse_flow_fields(fields)

    {callback_url, request_metadata} =
      build_flow_resume_metadata(organization_id, flow_id, contact_id, fields)

    request_metadata =
      Map.merge(request_metadata, %{call_type: "tts", webhook_name: "text_to_speech"})

    tts_opts = %{
      provider: fields["provider"],
      model: fields["model"],
      language: fields["language"],
      voice: fields["voice"]
    }

    Glific.Metrics.increment("Kaapi TTS Call", organization_id)

    with_failure_reporting("text_to_speech", organization_id, fn ->
      Kaapi.text_to_speech(organization_id, text, callback_url, request_metadata, tts_opts)
    end)
  end

  def webhook(function, fields, _headers), do: webhook(function, fields)

  def webhook("speech_to_text_with_bhasini", fields),
    do: Dispatcher.dispatch_named("speech_to_text_with_bhasini", fields)

  # Uses Gemini/Bhasini/OpenAI for TTS via Bhasini flow nodes.
  def webhook("text_to_speech_with_bhasini", fields),
    do: Dispatcher.dispatch_named("text_to_speech_with_bhasini", fields)

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map() | String.t()
  def webhook("parse_via_chat_gpt", fields) do
    org_id = parse_org_id(fields)

    with_failure_reporting("parse_via_chat_gpt", org_id, fn ->
      with {:ok, fields} <- parse_chatgpt_fields(fields),
           {:ok, fields} <- parse_response_format(fields),
           {:ok, text} <- Glific.get_open_ai_key() |> ChatGPT.parse(fields) do
        %{
          success: true,
          parsed_msg: parse_gpt_response(text)
        }
      else
        {:error, error} ->
          error
      end
    end)
  end

  @spec webhook(String.t(), map()) :: any()
  def webhook("parse_via_gpt_vision", fields) do
    url = fields["url"]
    org_id = parse_org_id(fields)

    # Failures return a bare string (not %{success: false}) so the flow routes
    # to the "Failure" category (lib/glific/flows/webhook.ex keys off is_map).
    with_failure_reporting("parse_via_gpt_vision", org_id, fn ->
      # validating if the url passed is a valid image url
      with %{is_valid: true} <- Glific.Messages.validate_media(url, "image"),
           {:ok, fields} <- maybe_inline_image(fields, url, org_id),
           {:ok, fields} <- parse_response_format(fields),
           {:ok, response} <- ChatGPT.gpt_vision(fields) do
        %{success: true, response: parse_gpt_response(response)}
      else
        %{is_valid: false, message: message} ->
          message

        {:error, error} ->
          error
      end
    end)
  end

  # Migrated to Glific.Flows.Webhooks.NmtTtsWithBhasini. This clause now routes
  # through the centralised dispatcher, which wraps the call with failure
  # reporting + latency telemetry.
  def webhook("nmt_tts_with_bhasini", fields),
    do: Dispatcher.dispatch_named("nmt_tts_with_bhasini", fields)

  # Migrated to Glific.Flows.Webhooks.DetectLanguage. This clause now routes
  # through the central dispatcher.
  def webhook("detect_language", fields),
    do: Dispatcher.dispatch_named("detect_language", fields)

  def webhook("get_buttons", fields) do
    buttons =
      fields["buttons_data"]
      |> String.split("|")
      |> Enum.with_index()
      |> Enum.map(fn {answer, index} -> {"button_#{index + 1}", String.trim(answer)} end)
      |> Enum.into(%{})

    %{
      buttons: buttons,
      button_count: length(Map.keys(buttons)),
      is_valid: true
    }
  end

  def webhook("check_response", fields),
    do: %{response: String.equivalent?(fields["correct_response"], fields["user_response"])}

  # Migrated to Glific.Flows.Webhooks.Geolocation. This clause now routes
  # through the centralised dispatcher, which wraps the call with failure
  # reporting + latency telemetry.
  def webhook("geolocation", fields),
    do: Dispatcher.dispatch_named("geolocation", fields)

  # Migrated to Glific.Flows.Webhooks.SendWaGroupPoll. This clause now routes
  # through the centralised dispatcher, which wraps the call with failure
  # reporting + latency telemetry.
  def webhook("send_wa_group_poll", fields),
    do: Dispatcher.dispatch_named("send_wa_group_poll", fields)

  # Migrated to Glific.Flows.Webhooks.CreateCertificate. This clause now routes
  # through the centralised dispatcher, which wraps the call with failure
  # reporting + latency telemetry.
  def webhook("create_certificate", fields),
    do: Dispatcher.dispatch_named("create_certificate", fields)

  def webhook(_, _fields), do: %{error: "Missing webhook function implementation"}

  @doc """
  Performs voice post-processing on a Kaapi LLM response: runs NMT+TTS to
  translate and generate audio, then merges translated_text and media_url
  into the response map.
  """
  @spec voice_post_process(non_neg_integer(), boolean(), map()) :: map()
  def voice_post_process(organization_id, success, response) do
    llm_response_text = response["message"] || ""
    voice_fields = response["voice_post_process"] || %{}

    tts_result =
      cond do
        success && llm_response_text != "" ->
          do_nmt_tts_with_bhasini(%{
            "text" => llm_response_text,
            "organization_id" => organization_id,
            "source_language" => voice_fields["source_language"],
            "target_language" => voice_fields["target_language"],
            "speech_engine" => voice_fields["speech_engine"] || ""
          })

        # Kaapi reported success but gave us no text to speak
        # sending error code 200 since the call from kaapi is success
        success ->
          report_webhook_failure(
            "unified-voice-llm-call",
            organization_id,
            200,
            "Kaapi callback returned success=true but message was empty/nil"
          )

          %{success: false, translated_text: "", media_url: nil}

        true ->
          %{success: false, translated_text: llm_response_text, media_url: nil}
      end

    translated_text = tts_result[:translated_text] || llm_response_text

    response
    |> Map.put("translated_text", translated_text)
    |> Map.put("media_url", tts_result[:media_url])
  end

  defp do_unified_llm_call(fields, headers, callback_url, request_metadata) do
    {_, org_api_key} = Enum.find(headers, fn {key, _v} -> key == "X-API-KEY" end)
    {organization_id, _, _} = parse_flow_fields(fields)

    with {:ok, {kaapi_uuid, version_number}} <-
           lookup_kaapi_config(fields["assistant_id"], organization_id),
         payload =
           build_unified_llm_payload(
             fields,
             kaapi_uuid,
             version_number,
             callback_url,
             request_metadata
           ),
         {:ok, body} <- ApiClient.call_llm(payload, org_api_key) do
      Kaapi.normalize_kaapi_body(body)
    else
      {:error, %{status: status, body: body}} ->
        %{success: false, reason: Jason.encode!(body), http_status: status}

      {:error, reason} when is_binary(reason) ->
        %{success: false, reason: reason}

      {:error, reason} ->
        %{success: false, reason: inspect(reason)}
    end
  end

  # Spec includes `{:error, _}` defensively so the unified-voice-llm-call call
  # site can keep an error-tuple match (even if Gemini.speech_to_text doesn't
  # currently surface one) without Dialyzer flagging the clause as unreachable.
  @spec do_speech_to_text_with_bhasini(map()) :: map() | String.t() | {:error, any()}
  defp do_speech_to_text_with_bhasini(fields) do
    {:ok, org_id} = fields["organization_id"] |> Glific.parse_maybe_integer()

    with_failure_reporting("speech_to_text_with_bhasini", org_id, fn ->
      case Bhasini.validate_params(fields) do
        {:ok, contact} ->
          Glific.Metrics.increment("Gemini STT Call", contact.organization_id)
          Gemini.speech_to_text(fields["speech"], contact.organization_id)

        {:error, error} ->
          %{success: false, asr_response_text: error}
      end
    end)
  end

  @spec do_nmt_tts_with_bhasini(map()) :: map() | String.t()
  defp do_nmt_tts_with_bhasini(fields) do
    text = fields["text"]
    {:ok, org_id} = fields["organization_id"] |> Glific.parse_maybe_integer()
    source_language = normalize_language(fields["source_language"])
    target_language = normalize_language(fields["target_language"])
    speech_engine = Map.get(fields, "speech_engine", "")

    with_failure_reporting("nmt_tts_with_bhasini", org_id, fn ->
      if source_language == target_language do
        handle_tts_only(source_language, org_id, text, speech_engine)
      else
        gemini_nmt_tts_call(source_language, target_language, org_id, text,
          speech_engine: speech_engine
        )
      end
    end)
  end

  @spec gemini_nmt_tts_call(
          String.t(),
          String.t(),
          non_neg_integer(),
          String.t(),
          Keyword.t()
        ) :: map()
  defp gemini_nmt_tts_call(source_language, target_language, org_id, text, opts) do
    organization = Partners.organization(org_id)
    services = organization.services["google_cloud_storage"]

    with false <- is_nil(services),
         true <- Gemini.valid_language?(source_language, target_language) do
      Glific.Metrics.increment("Gemini NMT TTS Call", org_id)
      Gemini.nmt_text_to_speech(org_id, text, source_language, target_language, opts)
    else
      true ->
        %{success: false, reason: "GCS is disabled"}

      false ->
        %{success: false, reason: "Language not supported in Gemini"}
    end
  end

  @spec normalize_language(String.t() | nil) :: String.t() | nil
  defp normalize_language(nil), do: ""
  defp normalize_language(language), do: String.downcase(language)

  @spec handle_tts_only(String.t(), non_neg_integer(), String.t(), String.t()) ::
          map() | String.t()
  defp handle_tts_only(language, org_id, text, speech_engine) do
    cond do
      speech_engine == "bhashini" ->
        Glific.Metrics.increment("Gemini NMT TTS Call", org_id)
        Gemini.text_to_speech(org_id, text)

      speech_engine == "open_ai" || language == "english" ->
        ChatGPT.text_to_speech_with_open_ai(org_id, text)

      true ->
        Glific.Metrics.increment("Gemini NMT TTS Call", org_id)
        Gemini.text_to_speech(org_id, text)
    end
  end

  @spec call_responses_and_format(map(), String.t()) :: map()
  defp call_responses_and_format(payload, org_api_key) do
    case ApiClient.call_responses_api(payload, org_api_key) do
      {:ok, body} ->
        Map.merge(%{success: true}, body)

      {:error, %{status: _status, body: body}} ->
        result = Jason.encode!(body)
        %{success: false, reason: result}

      {:error, reason} ->
        %{success: false, reason: inspect(reason)}
    end
  end

  defp parse_response_format(%{"response_format" => response_format} = fields) do
    case response_format do
      %{"type" => "json_schema"} ->
        # Support for json_schema is only since gpt-4o-2024-08-06
        {:ok, Map.put(fields, "model", "gpt-4o-2024-08-06")}

      %{"type" => "json_object"} ->
        {:ok, fields}

      nil ->
        {:ok, fields}

      _ ->
        {:error, "response_format type should be json_schema or json_object"}
    end
  end

  defp parse_response_format(fields), do: {:ok, Map.put(fields, "response_format", nil)}

  @spec parse_gpt_response(String.t()) :: any()
  defp parse_gpt_response(response) do
    case Jason.decode(response) do
      {:ok, decoded_response} ->
        decoded_response

      {:error, _err} ->
        response
    end
  end

  @spec parse_chatgpt_fields(map()) :: {:ok, map()} | {:error, String.t()}
  defp parse_chatgpt_fields(fields) do
    if fields["question_text"] in [nil, ""] do
      {:error, "question_text is empty"}
    else
      {:ok,
       %{
         "question_text" => Map.get(fields, "question_text"),
         "prompt" => Map.get(fields, "prompt", nil),
         # ID of the model to use.
         "model" => Map.get(fields, "model", "gpt-4o"),
         # The sampling temperature, between 0 and 1.
         # Higher values like 0.8 will make the output more random,
         # while lower values like 0.2 will make it more focused and deterministic.
         "temperature" => Map.get(fields, "temperature", 0),
         "response_format" => Map.get(fields, "response_format", nil)
       }}
    end
  end

  @spec parse_flow_fields(map()) :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  defp parse_flow_fields(fields) do
    with {:ok, organization_id} <- Glific.parse_maybe_integer(fields["organization_id"]),
         {:ok, flow_id} <- Glific.parse_maybe_integer(fields["flow_id"]),
         {:ok, contact_id} <- Glific.parse_maybe_integer(fields["contact_id"]) do
      {organization_id, flow_id, contact_id}
    else
      _ -> raise ArgumentError, "Invalid flow metadata for Kaapi webhook: #{inspect(fields)}"
    end
  end

  # Best-effort org_id for failure reporting tags. Returns nil if absent/unparseable
  # rather than raising, since it's only used for the AppSignal tag.
  @spec parse_org_id(map()) :: non_neg_integer() | nil
  defp parse_org_id(fields) do
    case Glific.parse_maybe_integer(fields["organization_id"]) do
      {:ok, id} -> id
      _ -> nil
    end
  end

  @spec maybe_inline_image(map(), String.t(), non_neg_integer() | nil) ::
          {:ok, map()} | {:error, String.t()}
  defp maybe_inline_image(fields, image_url, org_id) do
    if FunWithFlags.enabled?(:is_gpt_vision_base64_enabled, for: %{organization_id: org_id}) do
      case GupshupClient.download_media_content(image_url, org_id) do
        {:ok, encoded_image, content_type} ->
          # OpenAI needs a data URL (data:<mime>;base64,<...>), not bare base64.
          # Use the server's Content-Type since Gupshup media URLs carry no extension.
          mime = normalize_image_mime(content_type)
          {:ok, Map.put(fields, "url", "data:#{mime};base64,#{encoded_image}")}

        {:error, _reason} ->
          {:error, "Failed to download image for vision parsing"}
      end
    else
      {:ok, fields}
    end
  end

  @spec normalize_image_mime(String.t() | nil) :: String.t()
  defp normalize_image_mime(nil), do: "image/jpeg"

  defp normalize_image_mime(content_type),
    do: content_type |> String.split(";") |> hd() |> String.trim()

  # Webhook param validation hook. Single check today; convert to a
  # short-circuiting `with` once there's more than one field to validate.
  @spec validate_params(map()) :: :ok | {:error, String.t()}
  defp validate_params(fields), do: validate_media(fields["speech"])

  @spec validate_media(any()) :: :ok | {:error, String.t()}
  defp validate_media(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
        :ok

      _ ->
        {:error, "Media URL is invalid"}
    end
  end

  defp validate_media(_), do: {:error, "Media URL is needed"}

  # Builds the callback URL and request_metadata map needed for all Kaapi async calls
  # (unified-llm-call, STT, TTS). Centralises signature generation and callback URL construction.
  @spec build_flow_resume_metadata(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          map(),
          String.t()
        ) ::
          {String.t(), map()}
  defp build_flow_resume_metadata(
         organization_id,
         flow_id,
         contact_id,
         fields,
         callback_path \\ "/webhook/flow_resume",
         timestamp \\ nil
       ) do
    timestamp = timestamp || DateTime.utc_now() |> DateTime.to_unix(:microsecond)

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

    organization = Partners.organization(organization_id)

    callback_url = Glific.api_callback_base(organization.shortcode) <> callback_path

    request_metadata = %{
      organization_id: organization_id,
      flow_id: flow_id,
      contact_id: contact_id,
      timestamp: timestamp,
      signature: signature,
      webhook_log_id: fields["webhook_log_id"],
      result_name: fields["result_name"]
    }

    {callback_url, request_metadata}
  end

  @spec maybe_put_response_id(map(), map()) :: map()
  defp maybe_put_response_id(map, fields) do
    case fields["thread_id"] do
      nil -> map
      thread_id -> Map.put(map, "response_id", thread_id)
    end
  end

  @spec build_conversation(String.t() | nil) :: map()
  defp build_conversation(nil), do: %{auto_create: true}
  defp build_conversation(thread_id), do: %{id: thread_id}

  defp build_unified_llm_payload(
         fields,
         kaapi_uuid,
         version_number,
         callback_url,
         request_metadata
       ) do
    %{
      query: %{
        input: fields["question"],
        conversation: build_conversation(fields["thread_id"])
      },
      config: %{
        id: kaapi_uuid,
        version: version_number
      },
      callback_url: callback_url,
      request_metadata: request_metadata
    }
  end

  @spec lookup_kaapi_config(String.t() | nil, non_neg_integer()) ::
          {:ok, {String.t(), non_neg_integer()}} | {:error, String.t()}
  defp lookup_kaapi_config(assistant_display_id, _organization_id)
       when is_nil(assistant_display_id),
       do: {:error, "assistant_id is required"}

  defp lookup_kaapi_config(assistant_display_id, organization_id) do
    with {:ok, assistant} <-
           Repo.fetch_by(Assistant, %{
             assistant_display_id: assistant_display_id,
             organization_id: organization_id
           }),
         assistant <- Repo.preload(assistant, :active_config_version),
         {:ok, kaapi_uuid} <- fetch_kaapi_uuid(assistant),
         %{kaapi_version_number: kaapi_version_number} when not is_nil(kaapi_version_number) <-
           assistant.active_config_version do
      {:ok, {kaapi_uuid, kaapi_version_number}}
    else
      {:error, :missing_kaapi_uuid} ->
        {:error, "Assistant is still being set up"}

      {:error, _} ->
        {:error, "Assistant not found: #{assistant_display_id}"}

      nil ->
        {:error, "No active config version found for assistant #{assistant_display_id}"}

      %{kaapi_version_number: nil} ->
        {:error, "Kaapi version number not found"}
    end
  end

  @spec fetch_kaapi_uuid(map()) :: {:ok, String.t()} | {:error, :missing_kaapi_uuid}
  defp fetch_kaapi_uuid(%{kaapi_uuid: nil}), do: {:error, :missing_kaapi_uuid}
  defp fetch_kaapi_uuid(%{kaapi_uuid: uuid}), do: {:ok, uuid}

  # Webhooks whose real outcome arrives later via a flow_resume callback. Here we
  # only see the dispatch ack, so their success is counted at the callback
  # (GlificWeb.Flows.FlowResumeController) to avoid double counting.
  @async_webhooks ~w(speech_to_text text_to_speech unified-llm-call unified-voice-llm-call)

  @spec with_failure_reporting(String.t(), non_neg_integer() | nil, (-> any())) :: any()
  defp with_failure_reporting(webhook_name, org_id, fun) do
    start = System.monotonic_time(:millisecond)

    try do
      result = fun.()
      duration_ms = System.monotonic_time(:millisecond) - start
      record_webhook_outcome(result, webhook_name, org_id, duration_ms)
      result
    rescue
      exception ->
        duration_ms = System.monotonic_time(:millisecond) - start
        report_webhook_failure(webhook_name, org_id, nil, Exception.message(exception))
        record_webhook_metrics(webhook_name, "failure", duration_ms)
        reraise exception, __STACKTRACE__
    end
  end

  # FUNCTION webhooks signal Failure to the flow by returning a non-map (see
  # Glific.Flows.Webhook.handle/3, which keys off is_map). Convert a
  # %{success: false} result into a bare error string so the flow routes to the
  @spec record_webhook_outcome(any(), String.t(), non_neg_integer() | nil, non_neg_integer()) ::
          :ok
  defp record_webhook_outcome(%{success: false} = result, webhook_name, org_id, duration_ms) do
    {status, reason} = extract_status_and_reason(result)
    report_webhook_failure(webhook_name, org_id, status, reason)
    record_webhook_metrics(webhook_name, "failure", duration_ms)
  end

  # nil / non-map results route to the flow's Failure category (see
  # Glific.Flows.Webhook.handle/3, which keys off is_map). Treat them as
  # failures here too
  defp record_webhook_outcome(result, webhook_name, org_id, duration_ms)
       when is_nil(result) or not is_map(result) do
    reason = if is_binary(result), do: result, else: inspect(result)
    report_webhook_failure(webhook_name, org_id, nil, reason)
    record_webhook_metrics(webhook_name, "failure", duration_ms)
  end

  defp record_webhook_outcome(_result, webhook_name, _org_id, duration_ms) do
    unless webhook_name in @async_webhooks,
      do: record_webhook_metrics(webhook_name, "success", duration_ms)

    :ok
  end

  @spec record_webhook_metrics(String.t() | nil, String.t(), non_neg_integer()) :: :ok
  defp record_webhook_metrics(webhook_name, status, duration_ms) do
    Webhook.track_webhook_count(webhook_name, status)
    Webhook.track_webhook_latency(webhook_name, status, duration_ms)
    :ok
  end

  @spec extract_status_and_reason(map()) :: {integer() | nil, String.t() | nil}
  defp extract_status_and_reason(result) do
    case result do
      %{http_status: status, reason: reason} when is_integer(status) and is_binary(reason) ->
        {status, reason}

      %{http_status: status} when is_integer(status) ->
        {status, nil}

      %{asr_response_text: status} when is_integer(status) ->
        {status, nil}

      %{asr_response_text: status} when is_binary(status) ->
        {nil, status}

      %{reason: status} when is_binary(status) ->
        {nil, status}

      other ->
        {nil, inspect(other)}
    end
  end

  @spec report_webhook_failure(
          String.t(),
          non_neg_integer() | nil,
          integer() | nil,
          String.t() | nil
        ) :: :ok
  defp report_webhook_failure(webhook_name, org_id, http_status, reason) do
    %SystemError{message: "Webhook system_error from #{webhook_name}"}
    |> Webhook.report_to_appsignal(%{
      organization_id: org_id,
      webhook_name: webhook_name,
      http_status: http_status,
      reason: reason
    })
  end
end
