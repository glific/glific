defmodule Glific.ThirdParty.Gemini.ApiClient do
  @moduledoc """
  Client for interacting with Gemini via APIs.
  """
  require Logger
  alias Glific.Flows.Webhook.SystemError
  alias Glific.Metrics

  @gemini_url "https://generativelanguage.googleapis.com/v1beta/models"

  @doc """
  Performs STT call on the given content to Gemini.
  """
  @spec speech_to_text(String.t(), non_neg_integer()) :: map()
  def speech_to_text(encoded_audio, organization_id) do
    body = stt_request_body(encoded_audio)
    opts = [adapter: [recv_timeout: 300_000]]

    client()
    |> Tesla.post("/#{gemini_config(:stt_model)}:generateContent", body, opts: opts)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: %{candidates: candidates, usageMetadata: metadata}}} ->
        text =
          candidates
          |> get_in([Access.at(0), :content, :parts, Access.at(0), :text])
          |> Jason.decode!()

        stt_gemini_usage_stats(metadata, organization_id)

        %{success: true, asr_response_text: text}

      {:ok, %Tesla.Env{status: status_code}} ->
        report_gemini_failure("gemini_stt", status_code, organization_id)
        %{success: false, asr_response_text: status_code}

      {:error, %Tesla.Env{body: error_reason}} ->
        report_gemini_failure("gemini_stt", nil, organization_id)
        %{success: false, asr_response_text: error_reason}

      {:error, reason} ->
        report_gemini_failure("gemini_stt", nil, organization_id)
        %{success: false, asr_response_text: reason}
    end
  end

  @doc """
  Convert text to speech using Gemini API.
  """
  @spec text_to_speech(String.t(), non_neg_integer()) :: {:ok, binary()} | {:error, nil}
  def text_to_speech(text, organization_id) do
    body = tts_request_body(text)
    path = "/#{gemini_config(:tts_model)}:generateContent"
    opts = [adapter: [recv_timeout: 300_000]]

    client()
    |> Tesla.post(path, body, opts: opts)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: %{candidates: candidates, usageMetadata: metadata}}} ->
        decoded_audio =
          candidates
          |> get_in([Access.at(0), :content, :parts, Access.at(0), :inlineData, :data])
          |> Base.decode64!()

        tts_gemini_usage_stats(metadata, organization_id)
        {:ok, decoded_audio}

      {:ok, %Tesla.Env{status: status}} ->
        report_gemini_failure("gemini_tts", status, organization_id)
        {:error, nil}

      {:error, %Tesla.Env{}} ->
        report_gemini_failure("gemini_tts", nil, organization_id)
        {:error, nil}

      {:error, _reason} ->
        report_gemini_failure("gemini_tts", nil, organization_id)
        {:error, nil}
    end
  end

  # Private

  # Reports a Gemini API failure to AppSignal via a structured exception.
  # The `:message` field is kept low-cardinality so AppSignal groups identical
  # failures into one incident; per-occurrence detail (org, status) goes in
  # struct fields and is recorded as tags.
  @spec report_gemini_failure(String.t(), integer() | nil, non_neg_integer()) :: :ok
  defp report_gemini_failure(webhook_name, status, organization_id) do
    Glific.log_exception(%SystemError{
      message: "Webhook system_error from #{webhook_name}",
      webhook_name: webhook_name,
      organization_id: organization_id,
      http_status: status
    })
  end

  @spec gemini_config() :: map()
  defp gemini_config, do: Application.fetch_env!(:glific, __MODULE__)

  @spec gemini_config(atom()) :: String.t()
  defp gemini_config(key), do: gemini_config()[key]

  # client with runtime config (API key / base URL).
  @spec client() :: Tesla.Client.t()
  defp client do
    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, @gemini_url},
        {Tesla.Middleware.Headers, headers()},
        {Tesla.Middleware.JSON, engine_opts: [keys: :atoms]},
        {Tesla.Middleware.Telemetry, metadata: %{provider: "Gemini", sampling_scale: 10}}
      ] ++ Glific.get_tesla_retry_middleware(%{max_retries: 1})
    )
  end

  @spec headers() :: list()
  defp headers do
    [
      {"x-goog-api-key", gemini_config(:gemini_api_key)},
      {"Content-Type", "application/json"}
    ]
  end

  @spec stt_request_body(String.t()) :: map()
  defp stt_request_body(data) do
    %{
      "contents" => [
        %{
          "parts" => [
            %{
              "inline_data" => %{
                # We are hardcoding the mime type for now, since finding the mime type
                # requires additional DB query. audio/mp3 is working fine for ogg media.
                # audio/ogg is the mime type of most audio we receive.
                "mime_type" => "audio/mp3",
                "data" => data
              }
            },
            %{
              "text" => "Process the audio file and generate transcription in the same language."
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

  @spec tts_request_body(String.t()) :: map()
  defp tts_request_body(text) do
    %{
      "contents" => [
        %{
          "parts" => [
            %{
              "text" =>
                "Read aloud in warm and friendly tone, considering audience listening to you is based in India: #{text}"
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
      "model" => gemini_config(:tts_model)
    }
  end

  @spec stt_gemini_usage_stats(map(), non_neg_integer()) :: :ok
  defp stt_gemini_usage_stats(metadata, organization_id) do
    Metrics.increment("Gemini STT Usage", organization_id, metadata[:totalTokenCount])
  end

  @spec tts_gemini_usage_stats(map(), non_neg_integer()) :: :ok
  defp tts_gemini_usage_stats(metadata, organization_id) do
    Metrics.increment("Gemini TTS Usage", organization_id, metadata[:totalTokenCount])
  end
end
