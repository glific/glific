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
  alias Glific.Providers.Gupshup.ApiClient, as: GupshupClient
  alias Glific.ThirdParty.Gemini.ApiClient

  @supported_languages %{
    "tamil" => "ta",
    "kannada" => "kn",
    "malayalam" => "ml",
    "telugu" => "te",
    "assamese" => "as",
    "gujarati" => "gu",
    "bengali" => "bn",
    "punjabi" => "pa",
    "marathi" => "mr",
    "urdu" => "ur",
    "spanish" => "es",
    "english" => "en",
    "hindi" => "hi",
    "odia" => "or"
  }
  @doc """
  Converts speech audio to text using Gemini API.

  This function takes an audio file URL and uses Google's Gemini speech-to-text API
  to transcribe the audio content into text. It tracks success/failure metrics for
  monitoring purposes.

  ## Examples

      iex> Glific.ThirdParty.Gemini.speech_to_text("https://example.com/audio.mp3", 1)
      %{success: true, asr_response_text: "Hello, this is a transcription"}

      iex> Glific.ThirdParty.Gemini.speech_to_text("https://invalid.url/audio.mp3", 1)
      %{success: false, error: "Failed to fetch audio"}

  """
  @spec speech_to_text(String.t(), non_neg_integer()) :: map()
  def speech_to_text(audio_url, organization_id) do
    with {:ok, encoded_audio} <- GupshupClient.download_media_content(audio_url, organization_id),
         %{success: true} = response <- ApiClient.speech_to_text(encoded_audio, organization_id) do
      Metrics.increment("Gemini STT Success", organization_id)

      response
    else
      {:error, :download_failed} ->
        Metrics.increment("Gemini STT Failure", organization_id)
        %{success: false, asr_response_text: "File download failed"}

      error ->
        Metrics.increment("Gemini STT Failure", organization_id)
        error
    end
  end

  @doc """
  Converts text to speech using Gemini API and uploads the audio to Google Cloud Storage.

  This function takes text input and converts it to an MP3 audio file using Google's Gemini
  text-to-speech API. The resulting audio is uploaded to GCS and a URL is returned.

  ## Examples

      iex> Glific.ThirdParty.Gemini.text_to_speech(1, "Hello world")
      %{success: true, media_url: "https://storage.googleapis.com/...", translated_text: "Hello world"}

      iex> Glific.ThirdParty.Gemini.text_to_speech(1, "Error case")
      %{success: false, media_url: nil, translated_text: "Error case"}

  """
  @spec text_to_speech(integer(), String.t()) :: map() | String.t()
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

    ## Examples

      iex> Glific.ThirdParty.Gemini.nmt_text_to_speech(1, "Hello", "english", "hindi", [])
      %{success: true, media_url: "https://storage.googleapis.com/...", translated_text: "नमस्ते"}

      iex> Glific.ThirdParty.Gemini.nmt_text_to_speech(1, "Hello", "english", "spanish", speech_engine: "open_ai")
      %{success: true, media_url: "https://...", translated_text: "Hola"}

      iex> Glific.ThirdParty.Gemini.nmt_text_to_speech(1, "Hello", "english", "french", [])
      %{success: false, media_url: nil, translated_text: "Hello"}

  """
  @spec nmt_text_to_speech(non_neg_integer(), String.t(), String.t(), String.t(), Keyword.t()) ::
          map()
  def nmt_text_to_speech(organization_id, text, source_language, target_language, opts) do
    speech_engine = Keyword.get(opts, :speech_engine, "gemini")
    source_language = @supported_languages[source_language]
    target_language = @supported_languages[target_language]

    with {:ok, [translated_text]} when byte_size(translated_text) > 0 <-
           GoogleTranslate.translate(
             [text],
             source_language,
             target_language,
             org_id: organization_id,
             token_chunk_size: 600
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
  def valid_language?(source_language, target_language) do
    languages = Map.keys(@supported_languages)
    source_language in languages and target_language in languages
  end

  # Private
  @spec do_text_to_speech(non_neg_integer(), String.t()) :: map()
  defp do_text_to_speech(organization_id, text) do
    with {:ok, decoded_audio} <- ApiClient.text_to_speech(text, organization_id),
         {:ok, mp3_file, remote_name} <- download_encoded_file(decoded_audio),
         {:ok, media_meta} <- GcsWorker.upload_media(mp3_file, remote_name, organization_id) do
      File.rm(mp3_file)
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

  @spec choose_engine_and_do_tts(String.t(), non_neg_integer(), String.t()) :: map()
  defp choose_engine_and_do_tts("open_ai", organization_id, translated_text),
    do: ChatGPT.text_to_speech_with_open_ai(organization_id, translated_text)

  # Use Gemini in any other case
  defp choose_engine_and_do_tts(_speech_engine, organization_id, translated_text),
    do: do_text_to_speech(organization_id, translated_text)

  @spec download_encoded_file(binary()) :: {:ok, String.t(), String.t()} | String.t()
  defp download_encoded_file(decoded_audio) do
    uuid = Ecto.UUID.generate()
    remote_name = "Gemini/outbound/#{uuid}.mp3"

    pcm_file = System.tmp_dir!() <> "#{uuid}.pcm"
    mp3_file = System.tmp_dir!() <> "#{uuid}.mp3"
    File.write!(pcm_file, decoded_audio)

    case System.cmd(
           "ffmpeg",
           ["-f", "s16le", "-ar", "24000", "-ac", "1", "-i", pcm_file, mp3_file],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        File.rm(pcm_file)
        {:ok, mp3_file, remote_name}

      {output, exit_code} ->
        File.rm(pcm_file)
        Logger.error("Gemini TTS FFmpeg failed with exit code #{exit_code}: #{output}")
        "Error while converting file"
    end
  end
end
