defmodule Glific.Bhasini do
  @moduledoc """
  Bhasini Integration Module
  """

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

        encoded_audio =
          get_in(response, [
            "pipelineResponse",
            Access.at(0),
            "audio",
            Access.at(0),
            "audioContent"
          ])

        decoded_audio = Base.decode64!(encoded_audio)

        uuid = Ecto.UUID.generate()
        path = System.tmp_dir!() <> "#{uuid}.mp3"
        File.write!(path, decoded_audio)
        remote_name = "Bhasini/outbound/#{uuid}.mp3"

        {:ok, media_meta} =
          Glific.GCS.GcsWorker.upload_media(
            path,
            remote_name,
            org_id
          )

        %{success: true} |> Map.put(:media_url, media_meta.url)

      _ ->
        %{success: false, reason: "could not fetch data"}
    end
  end
end
