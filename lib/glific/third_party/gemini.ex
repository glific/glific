defmodule Glific.ThirdParty.Gemini do
  @moduledoc """
    Context module for Gemini.
  """
  use Publicist
  require Logger

  alias Glific.GCS.GcsWorker
  alias Glific.Metrics
  alias Glific.Partners
  alias Glific.ThirdParty.Gemini.ApiClient

  @doc """
  Converts speech audio to text using Gemini API.

  This function takes an audio file URL and uses Google's Gemini speech-to-text API
  to transcribe the audio content into text. It tracks success/failure metrics for
  monitoring purposes.

  ## Parameters

    * `audio_url` - The URL of the audio file to be transcribed (must be publicly accessible)
    * `organization_id` - The ID of the organization making the request (used for metrics tracking)

  ## Returns

  Returns a map with one of the following structures:

    * `%{success: true, asr_response_text: text}` - When transcription succeeds, where `text` is the transcribed content
    * Error response from the API client - When transcription fails (structure depends on the error type)

  ## Examples

      iex> Glific.ThirdParty.Gemini.speech_to_text("https://example.com/audio.mp3", 1)
      %{success: true, asr_response_text: "Hello, this is a transcription"}

      iex> Glific.ThirdParty.Gemini.speech_to_text("https://invalid.url/audio.mp3", 1)
      %{success: false, error: "Failed to fetch audio"}

  """
  def speech_to_text(audio_url, organization_id) do
    with %{success: true, asr_response_text: text} <- ApiClient.speech_to_text(audio_url) do
      Metrics.increment("Gemini STT Success", organization_id)

      %{success: true, asr_response_text: text}
    else
      error ->
        Metrics.increment("Gemini STT Failure", organization_id)
        error
    end
  end

  @doc """
  Converts text to speech using Gemini API and uploads the audio to Google Cloud Storage.

  This function takes text input and converts it to an MP3 audio file using Google's Gemini
  text-to-speech API. The resulting audio is uploaded to GCS and a URL is returned.

  ## Parameters

    * `organization_id` - The ID of the organization making the request
    * `text` - The text to be converted to speech

  ## Returns

  Returns a map with the following structure:

    * `%{success: true, media_url: url, translated_text: text}` - When conversion succeeds
    * `%{success: false, media_url: nil, translated_text: text}` - When conversion fails
    * A string error message if GCS is not enabled for the organization

  ## Examples

      iex> Glific.ThirdParty.Gemini.text_to_speech(1, "Hello world")
      %{success: true, media_url: "https://storage.googleapis.com/...", translated_text: "Hello world"}

      iex> Glific.ThirdParty.Gemini.text_to_speech(1, "Error case")
      %{success: false, media_url: nil, translated_text: "Error case"}

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
    with {:ok, decoded_audio} <- ApiClient.text_to_speech(text),
         {:ok, mp3_file, remote_name} <- download_encoded_file(decoded_audio),
         {:ok, media_meta} <- GcsWorker.upload_media(mp3_file, remote_name, organization_id) do
      Metrics.increment("Gemini TTS Success", organization_id)

      %{success: true}
      |> Map.put(:media_url, media_meta.url)
      |> Map.put(:translated_text, text)
    else
      {:error, _} ->
        Metrics.increment("Gemini TTS Failure", organization_id)
        %{success: false, media_url: nil, translated_text: text}

      error ->
        Metrics.increment("Gemini TTS Failure", organization_id)
        Logger.error("Gemini TTS Failure: Reason: #{inspect(error)}")
        %{success: false, media_url: nil, translated_text: text}
    end
  end

  defp download_encoded_file(decoded_audio) do
    uuid = Ecto.UUID.generate()
    remote_name = "Gemini/outbound/#{uuid}.mp3"

    pcm_file = System.tmp_dir!() <> "#{uuid}.pcm"
    mp3_file = System.tmp_dir!() <> "#{uuid}.mp3"
    File.write!(pcm_file, decoded_audio)

    try do
      System.cmd(
        "ffmpeg",
        ["-f", "s16le", "-ar", "24000", "-ac", "1", "-i", pcm_file, mp3_file],
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
end
