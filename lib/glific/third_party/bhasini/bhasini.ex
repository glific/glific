defmodule Glific.Bhasini do
  @moduledoc """
  Bhasini Integration Module
  """

  alias Glific.GCS.GcsWorker

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
  This function makes an API call to the Bhasini ASR service for NMT and TTS using the provided configuration parameters and returns the public media URL of the file.
  """
  @spec nmt_tts(map(), String.t(), String.t(), String.t(), non_neg_integer()) :: map()
  def nmt_tts(params, text, source_language, target_language, org_id) do
    authorization_name = params["pipelineInferenceAPIEndPoint"]["inferenceApiKey"]["name"]
    authorization_value = params["pipelineInferenceAPIEndPoint"]["inferenceApiKey"]["value"]
    url = params["pipelineInferenceAPIEndPoint"]["callbackUrl"]

    {nmt_service_id, tts_service_id} =
      get_pipeline_config(params, source_language, target_language)

    default_headers = [
      {authorization_name, authorization_value},
      {"Content-Type", "application/json"}
    ]

    body =
      %{
        "pipelineTasks" => [
          %{
            "taskType" => "translation",
            "config" => %{
              "language" => %{
                "sourceLanguage" => @language_codes["#{source_language}"]["iso_639_1"],
                "targetLanguage" => @language_codes["#{target_language}"]["iso_639_1"]
              },
              "serviceId" => nmt_service_id
            }
          },
          %{
            "taskType" => "tts",
            "config" => %{
              "language" => %{
                # If TTS comes after Translation, and Translation is done, say from Marathi to Hindi
                # then Source Language of TTS should be Hindi (ISO Code hi) because
                # the output of Translation (Translated text in Hindi) will be fed to Translation Model.
                "sourceLanguage" => @language_codes["#{target_language}"]["iso_639_1"]
              },
              "serviceId" => tts_service_id,
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

    case Tesla.post(url, Jason.encode!(body),
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

        uuid = Ecto.UUID.generate()
        path = download_encoded_file(response, uuid)

        remote_name = "Bhasini/outbound/#{uuid}.mp3"

        {:ok, media_meta} =
          GcsWorker.upload_media(
            path,
            remote_name,
            org_id
          )

        %{success: true}
        |> Map.put(:media_url, media_meta.url)
        |> Map.put(:translated_text, translated_text)

      _ ->
        %{success: false, reason: "could not fetch data"}
    end
  end

  @spec get_pipeline_config(map(), String.t(), String.t()) :: {String.t(), String.t()}
  defp get_pipeline_config(params, source_language, target_language) do
    [%{"taskType" => "translation"} = nmt_config, %{"taskType" => "tts"} = tts_config] =
      get_in(params, ["pipelineResponseConfig"])

    [nmt_service_json] =
      Enum.filter(nmt_config["config"], fn config ->
        config["language"]["sourceLanguage"] == @language_codes["#{source_language}"]["iso_639_1"] and
          config["language"]["targetLanguage"] ==
            @language_codes["#{target_language}"]["iso_639_1"]
      end)

    [tts_service_json] =
      Enum.filter(tts_config["config"], fn config ->
        config["language"]["sourceLanguage"] == @language_codes["#{target_language}"]["iso_639_1"]
      end)

    {nmt_service_json["serviceId"], tts_service_json["serviceId"]}
  end

  @doc """
  This function makes an API call to the Bhasini ASR service using the provided configuration parameters and returns the public media URL of the file.
  """
  @spec text_to_speech(map(), String.t(), non_neg_integer()) :: map()
  def text_to_speech(params, text, org_id) do
    authorization_name = params["pipelineInferenceAPIEndPoint"]["inferenceApiKey"]["name"]
    authorization_value = params["pipelineInferenceAPIEndPoint"]["inferenceApiKey"]["value"]
    url = params["pipelineInferenceAPIEndPoint"]["callbackUrl"]

    config =
      get_in(params, ["pipelineResponseConfig", Access.at(0), "config", Access.at(0)])

    source_language = config["language"]["sourceLanguage"]
    service_id = config["serviceId"]

    default_headers = [
      {authorization_name, authorization_value},
      {"Content-Type", "application/json"}
    ]

    body =
      %{
        "pipelineTasks" => [
          %{
            "taskType" => "tts",
            "config" => %{
              "language" => %{"sourceLanguage" => source_language},
              "serviceId" => service_id,
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

    case Tesla.post(url, Jason.encode!(body),
           headers: default_headers,
           opts: [adapter: [recv_timeout: 300_000]]
         ) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        response = Jason.decode!(body)
        uuid = Ecto.UUID.generate()
        path = download_encoded_file(response, uuid)

        remote_name = "Bhasini/outbound/#{uuid}.mp3"

        {:ok, media_meta} =
          GcsWorker.upload_media(
            path,
            remote_name,
            org_id
          )

        %{success: true} |> Map.put(:media_url, media_meta.url)

      _ ->
        %{success: false, reason: "could not fetch data"}
    end
  end

  # Basically saving decoding the encoded audio and saving it
  # locally before uploading it to GCS to get public URL of file to be used at flow level
  @spec download_encoded_file(map(), String.t()) :: String.t()
  defp download_encoded_file(response, uuid) do
    pipeline_response =
      get_in(response, ["pipelineResponse"])
      |> Enum.filter(fn response -> response["taskType"] == "tts" end)

    encoded_audio =
      get_in(pipeline_response, [Access.at(0), "audio", Access.at(0), "audioContent"])

    decoded_audio = Base.decode64!(encoded_audio)
    path = System.tmp_dir!() <> "#{uuid}.mp3"
    :ok = File.write!(path, decoded_audio)
    path
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
