defmodule Glific.ASR.GoogleASR do
  @moduledoc """
  This is a module to convert speech to text
  """
  @hackney Tesla.Adapter.Hackney
  use Tesla

  require Logger

  alias Glific.Partners

  @doc """
  This function will take organization_id and the url for audio.
     * encoding: We have a list of endoing which is supported with these google api for more information check here
       https://cloud.google.com/speech-to-text/docs/encoding

     * Sample rate in Hertz of the audio data sent in all RecognitionAudio messages. Valid values are: 8000-48000. 16000 is optimal.
       For best results, set the sampling rate of the audio source to 16000 Hz. If that's not possible, use the native sample rate
       of the audio source (instead of re-sampling). This field is optional for FLAC and WAV audio files, but is required for all
       other audio formats

     * languageCode: This field support multiple languages to more info check this links
          1. https://www.rfc-editor.org/rfc/bcp/bcp47.txt
          2. https://cloud.google.com/speech-to-text/docs/languages

     *  profanityFilter: If enabled, Speech-to-Text will attempt to detect profane words and return only the first letter followed by asterisks in the
        transcript (for example, f***).

     *  enableWordConfidence: You can specify that Speech-to-Text indicate a value of accuracy, or confidence level, for individual words in a transcription.

     *  enableAutomaticPunctuation:  When you enable this feature, Speech-to-Text automatically infers the presence of periods, commas, and question marks in your audio data and adds them to the transcript.
  """

  @spec speech_to_text(non_neg_integer, String.t(), String.t()) :: map()
  def speech_to_text(org_id, uri, language) do
    {:ok, response} = get(uri)
    content = Base.encode64(response.body)

    url = "v1/speech:recognize"

    body = %{
      "config" => %{
        "encoding" => "OGG_OPUS",
        "sampleRateHertz" => 16_000,
        "languageCode" => language,
        "profanityFilter" => true,
        "enableWordConfidence" => true,
        "enableAutomaticPunctuation" => true
      },
      "audio" => %{
        "content" => content
      }
    }

    {:ok, result} = post(new_client(org_id), url, body)

    case result.body["error"] do
      nil ->
        successful_result_for_speech_to_text(result)

      res ->
        Logger.info("Oops! Something is wrong, #{inspect(res["message"])}")
    end
  end

  @spec successful_result_for_speech_to_text(map()) :: map() | {:error, String.t()}
  defp successful_result_for_speech_to_text(result) do
    case result.body["results"] do
      nil ->
        {:error, "Please check the link or Send the audio again"}

      res ->
        res |> get_in([Access.at(0), "alternatives"]) |> List.first()
    end
  end

  @spec new_client(non_neg_integer) :: Tesla.Client.t()
  defp new_client(org_id) do
    token = Partners.get_goth_token(org_id, "google_asr").token

    middleware = [
      {Tesla.Middleware.BaseUrl, "https://speech.googleapis.com/"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{token}"},
         {"Content-Type", "application/json"}
       ]}
    ]

    Tesla.client(middleware, @hackney)
  end
end
