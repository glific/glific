defmodule Glific.ThirdParty.Gemini.ApiClient do
  @moduledoc """
  Client for interacting with Gemini via APIs.
  """
  use Publicist
  require Logger

  alias Glific.GCS.GcsWorker
  alias Glific.Metrics
  alias Glific.Partners

  @gemini_url "https://generativelanguage.googleapis.com/v1beta/models"

  @doc """
  Performs STT call on the given content to Gemini.
  """
  @spec speech_to_text(String.t(), String.t()) :: any()
  def speech_to_text(audio_url, organization_id) do
    body = stt_request_body(audio_url)
    opts = [adapter: [recv_timeout: 300_000]]

    client()
    |> Tesla.post("/gemini-2.5-pro:generateContent", body, opts: opts)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: %{candidates: candidates, usageMetadata: metadata}}} ->
        text =
          candidates
          |> get_in([Access.at(0), :content, :parts, Access.at(0), :text])
          |> Jason.decode!()

        gemini_usage_stats(metadata)
        Metrics.increment("Gemini STT Success", organization_id)

        %{success: true, asr_response_text: text}

      {:ok, %Tesla.Env{status: status_code, body: body}} ->
        Metrics.increment("Gemini STT Failure", organization_id)
        Logger.error("Gemini STT Failure: #{status_code} Body: #{inspect(body)}")
        %{success: false, asr_response_text: status_code}

      {:error, %Tesla.Env{body: error_reason}} ->
        Metrics.increment("Gemini STT Failure", organization_id)
        Logger.error("Gemini STT Failure: Reason: #{inspect(error_reason)}")
        %{success: false, asr_response_text: error_reason}

      {:error, reason} ->
        Metrics.increment("Gemini STT Failure", organization_id)
        Logger.error("Gemini STT Failure: Reason: #{inspect(reason)}")
        %{success: false, asr_response_text: reason}
    end
  end

  @doc """
  Convert text to speech using Gemini API.
  """
  @spec text_to_speech(integer(), String.t()) :: map()
  def text_to_speech(organization_id, text) do
    organization = Partners.organization(organization_id)
    services = organization.services["google_cloud_storage"]

    if is_nil(services) do
      "Enable GCS is use Gemini text to speech"
    else
      do_text_to_speech(organization_id, text)
    end
  end

  # Private
  defp do_text_to_speech(organization_id, text) do
    body = tts_request_body(text)
    path = "/gemini-2.5-pro-preview-tts:generateContent"
    opts = [adapter: [recv_timeout: 300_000]]

    with {:ok, %Tesla.Env{status: 200, body: %{candidates: candidates, usageMetadata: metadata}}} <-
           Tesla.post(client(), path, body, opts: opts),
         {:ok, mp3_file, remote_name} <- download_encoded_file(candidates, organization_id),
         {:ok, media_meta} <- GcsWorker.upload_media(mp3_file, remote_name, organization_id) do
      gemini_usage_stats(metadata)

      %{success: true}
      |> Map.put(:media_url, media_meta.url)
      |> Map.put(:translated_text, text)
    else
      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Gemini TTS Failure: #{status}, Body: #{inspect(body)}")
        %{success: false, media_url: nil, translated_text: text}

      {:error, %Tesla.Env{body: error_reason}} ->
        Metrics.increment("Gemini TTS Failure", organization_id)
        Logger.error("Gemini TTS Failure: Reason: #{inspect(error_reason)}")
        %{success: false, media_url: nil, translated_text: text}

      {:error, reason} ->
        Metrics.increment("Gemini TTS Failure", organization_id)
        Logger.error("Gemini TTS Failure: Reason: #{inspect(reason)}")
        %{success: false, media_url: nil, translated_text: text}

      error ->
        Metrics.increment("Gemini TTS Failure", organization_id)
        Logger.error("Gemini TTS Failure: Reason: #{inspect(error)}")
        %{success: false, media_url: nil, translated_text: text}
    end
  end

  @spec gemini_config() :: map()
  defp gemini_config, do: Application.fetch_env!(:glific, __MODULE__)

  @spec gemini_config(atom()) :: String.t()
  defp gemini_config(key), do: gemini_config()[key]

  # client with runtime config (API key / base URL).
  @spec client() :: Tesla.Client.t()
  defp client() do
    Glific.Metrics.increment("Kaapi Requests")

    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, @gemini_url},
        {Tesla.Middleware.Headers, headers()},
        {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
        {Tesla.Middleware.Telemetry, metadata: %{provider: "Gemini", sampling_scale: 10}}
      ] ++ Glific.get_tesla_retry_middleware()
    )
  end

  @spec headers() :: list()
  defp headers() do
    [
      {"x-goog-api-key", gemini_config(:gemini_api_key)},
      {"Content-Type", "application/json"}
    ]
  end

  defp stt_request_body(audio_url) do
    %{
      "contents" => [
        %{
          "parts" => [
            %{
              "file_data" => %{
                "file_uri" => audio_url
              }
            },
            %{
              "text" =>
                "Process the audio file and generate transcription.\n\nRequirements:\n1. Detect the primary language of the audio.\n2. Identify the primary emotion of the speaker in the audio. You MUST choose exactly one of the following: Happy, Sad, Angry, Neutral."
            }
          ]
        }
      ],
      "generation_config" => %{
        "response_mime_type" => "application/json",
        "response_schema" => %{
          "type" => "STRING"
        }
      }
    }
  end

  defp tts_request_body(text) do
    %{
      "contents" => [
        %{
          "parts" => [
            %{
              "text" => text
            }
          ]
        }
      ],
      "generationConfig" => %{
        "responseModalities" => ["AUDIO"],
        "speechConfig" => %{
          "voiceConfig" => %{
            "prebuiltVoiceConfig" => %{
              "voiceName" => "Kore"
            }
          }
        }
      },
      "model" => "gemini-2.5-pro-preview-tts"
    }
  end

  defp download_encoded_file(candidates, organization_id) do
    decoded_audio =
      candidates
      |> get_in([Access.at(0), :content, :parts, Access.at(0), :inlineData, :data])
      |> Base.decode64!()

    Metrics.increment("Gemini TTS Success", organization_id)

    uuid = Ecto.UUID.generate()
    remote_name = "Gemini/outbound/#{uuid}.mp3"

    pcm_file = System.tmp_dir!() <> "#{uuid}.pcm"
    mp3_file = System.tmp_dir!() <> "#{uuid}.mp3"
    File.write!(pcm_file, decoded_audio)

    try do
      System.cmd("ffmpeg", ["-f", "s16le", "-ar", "24000", "-ac", "1", "-i", pcm_file, mp3_file],
        stderr_to_stdout: true
      )

      File.rm(pcm_file)
      {:ok, mp3_file, remote_name}
    catch
      error, reason ->
        Logger.info("Gemini TTS Failed: Downloaded with error: #{error} and reason: #{reason}")
        "Error while converting file"
    end
  end

  defp gemini_usage_stats(_metadata) do
    # TODO: Implement usage stats calculation
  end
end
