defmodule Glific.Bhasini do
  @moduledoc """
  Bhasini Integration Module
  """

  alias Glific.GCS.GcsWorker

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
    encoded_audio =
      get_in(response, [
        "pipelineResponse",
        Access.at(0),
        "audio",
        Access.at(0),
        "audioContent"
      ])

    decoded_audio = Base.decode64!(encoded_audio)

    path = System.tmp_dir!() <> "#{uuid}.mp3"
    :ok = File.write!(path, decoded_audio)
    path
  end
end
