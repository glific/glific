defmodule Glific.ThirdParty.Gemini do
  @moduledoc """
    Context module for Gemini.
  """
  use Publicist
  require Logger

  alias Glific.Flows.Translate.GoogleTranslate
  alias Glific.GCS.GcsWorker
  alias Glific.Metrics
  alias Glific.OpenAI.ChatGPT
  alias Glific.Partners
  alias Glific.ThirdParty.Gemini.ApiClient

  @supported_languages ["tamil", "telugu", "bengali", "marathi", "spanish", "english", "hindi"]

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
      "Enable GCS to use Gemini text to speech"
    else
      do_text_to_speech(organization_id, text)
    end
  end

  @doc """
  Translates text and converts it to speech using Neural Machine Translation (NMT) and text-to-speech.

  This function combines Google Translate's NMT capabilities with text-to-speech synthesis to translate
  text from one language to another and then generate audio of the translated text. It supports multiple
  speech engines including Gemini (default) and OpenAI.

  ## Parameters

    * `organization_id` - The ID of the organization making the request
    * `text` - The source text to be translated and converted to speech
    * `source_language` - The language code of the source text (e.g., "english", "hindi", "tamil")
    * `target_language` - The language code to translate to (e.g., "spanish", "marathi", "bengali")
    * `opts` - A keyword list of options:
      * `:speech_engine` - The TTS engine to use, either "open_ai" or "gemini" (default: "gemini")
      * Additional options passed to Google Translate API

  ## Returns

  Returns a map with one of the following structures:

    * `%{success: true, media_url: url, translated_text: text}` - When translation and TTS succeed
    * `%{success: false, media_url: nil, translated_text: text}` - When translation or TTS fail

    ## Examples

      iex> Glific.ThirdParty.Gemini.nmt_text_to_speech(1, "Hello", "english", "hindi", [])
      %{success: true, media_url: "https://storage.googleapis.com/...", translated_text: "नमस्ते"}

      iex> Glific.ThirdParty.Gemini.nmt_text_to_speech(1, "Hello", "english", "spanish", speech_engine: "open_ai")
      %{success: true, media_url: "https://...", translated_text: "Hola"}

      iex> Glific.ThirdParty.Gemini.nmt_text_to_speech(1, "Hello", "english", "french", [])
      %{success: false, media_url: nil, translated_text: "Hello"}

  """
  def nmt_text_to_speech(organization_id, text, source_language, target_language, opts) do
    speech_engine = Keyword.get(opts, :speech_engine, "gemini")
    source_language = String.capitalize(source_language)
    target_language = String.capitalize(target_language)

    with {:ok, [translated_text]} when byte_size(translated_text) > 0 <-
           GoogleTranslate.translate(
             [text],
             source_language,
             target_language,
             org_id: organization_id
           ),
         %{success: true} = response <-
           choose_engine_and_do_tts(speech_engine, organization_id, translated_text) do
      response
    else
      %{success: false} ->
        Metrics.increment("Gemini TTS Failure", organization_id)
        %{success: false, media_url: nil, translated_text: text}

      error ->
        Metrics.increment("Gemini NMT TTS Failure", organization_id)
        Logger.error("Google Translate Error: #{inspect(error)}")
        %{success: false, media_url: nil, translated_text: text}
    end
  end

  @doc """
  This function validates Gemini supported languages.
  """
  @spec valid_language?(String.t(), String.t()) :: boolean()
  def valid_language?(source_language, target_language),
    do: source_language in @supported_languages and target_language in @supported_languages

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

  defp choose_engine_and_do_tts("open_ai", organization_id, translated_text),
    do: ChatGPT.text_to_speech_with_open_ai(organization_id, translated_text)

  # Use Gemini in any other case
  defp choose_engine_and_do_tts(_speech_engine, organization_id, translated_text),
    do: do_text_to_speech(organization_id, translated_text)

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
