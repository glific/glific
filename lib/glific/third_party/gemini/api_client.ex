defmodule Glific.ThirdParty.Gemini.ApiClient do
  @moduledoc """
  Client for interacting with Gemini via APIs.
  """
  require Logger

  alias Glific.Metrics

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

  # Private
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

  defp gemini_usage_stats(_metadata) do
    # TODO: Implement usage stats calculation
  end
end
