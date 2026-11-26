defmodule Glific.Flows.Webhooks.VoiceSts do
  @moduledoc """
  Speech-to-speech path of the `voice-filesearch-gpt` node (behind `voice_sts_enabled`): downloads
  the incoming audio and hands it to Kaapi's STT -> LLM -> TTS chain. Kaapi sends one callback per
  block; `ChainProgress` keeps the intermediate ones and the final (audio) one resumes the flow.
  """

  alias Glific.Flows.Webhooks.Behaviour
  alias Glific.Flows.Webhooks.ChainProgress
  alias Glific.Flows.Webhooks.ErrorReporter
  alias Glific.Flows.Webhooks.ErrorType
  alias Glific.Flows.Webhooks.Instrumentation
  alias Glific.Flows.Webhooks.Kaapi, as: KaapiWebhook
  alias Glific.Providers.Gupshup.ApiClient, as: GupshupClient
  alias Glific.ThirdParty.Kaapi

  @webhook_name "voice-filesearch-gpt"

  @doc """
  Fires the voice pipeline: downloads the audio, then the async Kaapi speech-to-speech call.
  """
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

    with :ok <- KaapiWebhook.validate_media(fields["speech"]),
         {:ok, audio} <- download_audio(fields["speech"], organization_id) do
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
          call_type: "voice_sts",
          webhook_name: @webhook_name,
          audio_size_bucket: Instrumentation.size_bucket(audio.byte_size),
          kaapi_dispatch_ts: DateTime.utc_now() |> DateTime.to_unix(:microsecond)
        })

      fields
      |> KaapiWebhook.call_sts([{"X-API-KEY", api_key}], callback_url, request_metadata, audio)
      |> KaapiWebhook.to_result()
    end
  end

  @spec download_audio(String.t(), non_neg_integer()) ::
          {:ok, %{base64: String.t(), mime_type: String.t(), byte_size: non_neg_integer()}}
          | {:error, ErrorType.t(), String.t()}
  defp download_audio(url, organization_id) do
    case GupshupClient.download_media_content(url, organization_id) do
      {:ok, base64, content_type} ->
        {:ok,
         %{
           base64: base64,
           mime_type: content_type || "audio/ogg",
           byte_size: div(byte_size(base64) * 3, 4)
         }}

      {:error, _reason} ->
        {:error, :invalid_media_url, "Could not download the voice note"}
    end
  end

  @doc "Shapes the final callback: answer, transcript and conversation id from the webhook log."
  @spec handle_callback(map(), map(), Behaviour.ctx()) :: map()
  def handle_callback(%{"success" => true}, %{"success" => false} = response, _ctx) do
    response
  end

  def handle_callback(%{"success" => true}, response, %{organization_id: organization_id}) do
    {:ok, organization_id} = Glific.parse_maybe_integer(organization_id)
    stash = ChainProgress.take(organization_id, response["webhook_log_id"])
    answer = stash["text"] || ""
    media_url = response["message"]

    if answer == "", do: report_empty_answer(organization_id)

    response
    |> Map.put("message", answer)
    |> Map.put("translated_text", answer)
    |> Map.put("transcript", stash["stt"])
    |> Map.put("thread_id", stash["thread_id"] || response["thread_id"])
    |> Map.put("media_url", media_url)
  end

  def handle_callback(_result, %{"tts_failed" => true} = response, _ctx), do: response

  def handle_callback(_result, response, _ctx) do
    response
  end

  @spec report_empty_answer(non_neg_integer()) :: :ok
  defp report_empty_answer(organization_id) do
    ErrorReporter.report(
      :unknown,
      "STS final callback arrived without an LLM answer in the webhook log",
      %{
        organization_id: organization_id,
        webhook_name: @webhook_name
      }
    )
  end
end
