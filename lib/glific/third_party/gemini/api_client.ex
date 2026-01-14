defmodule Glific.ThirdParty.Gemini.ApiClient do
  @moduledoc """
  Client for interacting with Gemini via APIs.
  """
  require Logger

  defmodule Error do
    @moduledoc """
    Custom error module for Gemini API failures.
    Reporting these failures to AppSignal lets us detect and fix issues.
    """
    defexception [:message, :status_code]
  end

  @gemini_url "https://generativelanguage.googleapis.com/v1beta/models"

  @doc """
  Performs STT call on the given content to Gemini.
  """
  @spec speech_to_text(String.t(), non_neg_integer()) :: map()
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

        stt_gemini_usage_stats(metadata, organization_id)

        %{success: true, asr_response_text: text}

      {:ok, %Tesla.Env{status: status_code, body: body}} ->
        Glific.log_exception(%Error{
          message: "Gemini STT Failure: #{inspect(body)}",
          status_code: status_code
        })

        %{success: false, asr_response_text: status_code}

      {:error, %Tesla.Env{body: error_reason}} ->
        Glific.log_exception(%Error{message: "Gemini STT Failure: #{inspect(error_reason)}"})
        %{success: false, asr_response_text: error_reason}

      {:error, reason} ->
        Glific.log_exception(%Error{message: "Gemini STT Failure: #{inspect(reason)}"})
        %{success: false, asr_response_text: reason}
    end
  end

  @doc """
  Convert text to speech using Gemini API.
  """
  @spec text_to_speech(String.t(), non_neg_integer()) :: {:ok, binary()} | {:error, nil}
  def text_to_speech(text, organization_id) do
    body = tts_request_body(text)
    path = "/gemini-2.5-pro-preview-tts:generateContent"
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

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Glific.log_exception(%Error{
          message: "Gemini TTS Failure: #{inspect(body)}",
          status_code: status
        })

        {:error, nil}

      {:error, %Tesla.Env{body: error_reason}} ->
        Glific.log_exception(%Error{message: "Gemini TTS Failure: #{inspect(error_reason)}"})
        {:error, nil}

      {:error, reason} ->
        Glific.log_exception(%Error{message: "Gemini TTS Failure: #{inspect(reason)}"})
        {:error, nil}
    end
  end

  # Private
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
      "model" => "gemini-2.5-pro-preview-tts"
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
