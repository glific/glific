defmodule Glific.Bhasini do
  @moduledoc """
  Bhashini Integration Module
  """

  require Logger
  alias Glific.GCS.GcsWorker

  @callback_url "https://dhruva-api.bhashini.gov.in/services/inference/pipeline"
  @tts_service_id "Bhashini/IITM/TTS"
  @translation_service_id "ai4bharat/indictrans-v2-all-gpu--t4"
  @language_codes %{
    "tamil" => %{"iso_639_1" => "ta", "iso_639_2" => "tam"},
    "kannada" => %{"iso_639_1" => "kn", "iso_639_2" => "kan"},
    "malayalam" => %{"iso_639_1" => "ml", "iso_639_2" => "mal"},
    "telugu" => %{"iso_639_1" => "te", "iso_639_2" => "tel"},
    "assamese" => %{"iso_639_1" => "as", "iso_639_2" => "asm"},
    "gujarati" => %{"iso_639_1" => "gu", "iso_639_2" => "guj"},
    "bengali" => %{"iso_639_1" => "bn", "iso_639_2" => "ben"},
    "punjabi" => %{"iso_639_1" => "pa", "iso_639_2" => "pan"},
    "marathi" => %{"iso_639_1" => "mr", "iso_639_2" => "mar"},
    "urdu" => %{"iso_639_1" => "ur", "iso_639_2" => "urd"},
    "spanish" => %{"iso_639_1" => "es", "iso_639_2" => "spa"},
    "english" => %{"iso_639_1" => "en", "iso_639_2" => "eng"},
    "hindi" => %{"iso_639_1" => "hi", "iso_639_2" => "hin"}
  }

  @doc """
  returns iso_code for a language given the standard
  """
  @spec get_iso_code(String.t(), String.t()) :: String.t()
  def get_iso_code(language, standard) do
    language
    |> String.downcase()
    |> then(&@language_codes["#{&1}"][standard])
  end

  @doc """
  This function makes an API call to the Bhashini ASR service for NMT and TTS using the provided configuration parameters and returns the public media URL of the file.
  """
  @spec nmt_tts(String.t(), String.t(), String.t(), non_neg_integer()) :: map()
  def nmt_tts(text, source_language, target_language, org_id) do
    bhashini_keys = Glific.get_bhashini_keys()

    default_headers = [
      {"Authorization", bhashini_keys.inference_key},
      {"Content-Type", "application/json"}
    ]

    body =
      %{
        "pipelineTasks" => [
          %{
            "taskType" => "translation",
            "config" => %{
              "language" => %{
                "sourceLanguage" => get_iso_code(source_language, "iso_639_1"),
                "targetLanguage" => get_iso_code(target_language, "iso_639_1")
              },
              "serviceId" => @translation_service_id
            }
          },
          %{
            "taskType" => "tts",
            "config" => %{
              "language" => %{
                # If TTS comes after Translation, and Translation is done, say from Marathi to Hindi
                # then Source Language of TTS should be Hindi (ISO Code hi) because
                # the output of Translation (Translated text in Hindi) will be fed to Translation Model.
                "sourceLanguage" => get_iso_code(target_language, "iso_639_1")
              },
              "serviceId" => @tts_service_id,
              "gender" => "female",
              "samplingRate" => 8000
            }
          }
        ],
        "inputData" => %{
          "input" => [
            %{"source" => text}
          ]
        }
      }

    case Tesla.post(@callback_url, Jason.encode!(body),
           headers: default_headers,
           opts: [adapter: [recv_timeout: 300_000]]
         ) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        response = Jason.decode!(body)

        translated_text =
          get_in(response, [
            "pipelineResponse",
            Access.at(0),
            "output",
            Access.at(0),
            "target"
          ])

        process_media(translated_text, response, org_id)

      {:ok, %Tesla.Env{status: 500, body: body}} ->
        %{success: false, reason: body}

      error ->
        Logger.info("Error from Bhashini: #{error}")
        %{success: false, reason: "could not fetch data"}
    end
  end

  defp process_media(translated_text, response, org_id) do
    uuid = Ecto.UUID.generate()
    remote_name = "Bhasini/outbound/#{uuid}.mp3"

    with {:ok, path} <- download_encoded_file(response, uuid),
         {:ok, media_meta} <-
           GcsWorker.upload_media(
             path,
             remote_name,
             org_id
           ) do
      File.rm(path)

      %{success: true}
      |> Map.put(:media_url, media_meta.url)
      |> Map.put(:translated_text, translated_text)
    end
  end

  @doc """
  This function makes an API call to the Bhashini ASR service using the provided configuration parameters and returns the public media URL of the file.
  """
  @spec text_to_speech(String.t(), non_neg_integer(), String.t()) :: map()
  def text_to_speech(source_language, org_id, text) do
    bhashini_keys = Glific.get_bhashini_keys()

    source_language = get_iso_code(source_language, "iso_639_1")

    default_headers = [
      {"Authorization", bhashini_keys.inference_key},
      {"Content-Type", "application/json"}
    ]

    body =
      %{
        "pipelineTasks" => [
          %{
            "taskType" => "tts",
            "config" => %{
              "language" => %{"sourceLanguage" => source_language},
              "serviceId" => @tts_service_id,
              "gender" => "female",
              "samplingRate" => 8000
            }
          }
        ],
        "inputData" => %{
          "input" => [
            %{"source" => text}
          ]
        }
      }

    case Tesla.post(@callback_url, Jason.encode!(body),
           headers: default_headers,
           opts: [adapter: [recv_timeout: 300_000]]
         ) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        response = Jason.decode!(body)
        uuid = Ecto.UUID.generate()
        remote_name = "Bhasini/outbound/#{uuid}.mp3"

        with {:ok, path} <- download_encoded_file(response, uuid),
             {:ok, media_meta} <-
               GcsWorker.upload_media(
                 path,
                 remote_name,
                 org_id
               ) do
          %{success: true}
          |> Map.put(:media_url, media_meta.url)
          |> Map.put(:translated_text, text)
        end

      {:ok, %Tesla.Env{body: body}} ->
        %{success: false, reason: body}

      error ->
        Logger.info("Error from Bhashini: #{error}")
        %{success: false, reason: "could not fetch data"}
    end
  end

  @doc """
  Basically saving decoding the encoded audio and saving it
  locally before uploading it to GCS to get public URL of file to be used at flow level
  """
  @spec download_encoded_file(map(), String.t()) :: {:ok, String.t()} | String.t()
  def download_encoded_file(response, uuid) do
    pipeline_response =
      get_in(response, ["pipelineResponse"])
      |> Enum.filter(fn response -> response["taskType"] == "tts" end)

    encoded_audio =
      get_in(pipeline_response, [Access.at(0), "audio", Access.at(0), "audioContent"])

    decoded_audio = Base.decode64!(encoded_audio)
    wav_file = System.tmp_dir!() <> "#{uuid}.wav"
    mp3_file = System.tmp_dir!() <> "#{uuid}.mp3"
    File.write!(wav_file, decoded_audio)

    try do
      System.cmd("ffmpeg", ["-i", wav_file, mp3_file], stderr_to_stdout: true)
      File.rm(wav_file)
      {:ok, mp3_file}
    catch
      error, reason ->
        Logger.info("Bhasini Downloaded with error: #{error} and reason: #{reason}")
        "Error while converting file"
    end
  end

  @doc """
  This function validates supported languages in Glific before sending to Bhasini
  """
  @spec valid_language?(String.t(), String.t()) :: boolean()
  def valid_language?(source_language, target_language) do
    valid_languages = Map.keys(@language_codes)

    source_language in valid_languages and target_language in valid_languages
  end
end
