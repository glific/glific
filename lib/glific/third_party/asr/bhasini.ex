defmodule Glific.ASR.Bhasini do
  @moduledoc """
  This is a module to convert speech to text by using bhasini api
  """
  use Tesla

  defp make_asr_api_call(
         authorization_key,
         authorization_value,
         callback_url,
         asr_service_id,
         source_language,
         base64_data
       ) do
    asr_headers = [
      {"#{authorization_key}", "#{authorization_value}"},
      {"Content-Type", "application/json"}
    ]

    asr_post_body = %{
      "pipelineTasks" => [
        %{
          "taskType" => "asr",
          "config" => %{
            "language" => %{
              "sourceLanguage" => "#{source_language}"
            },
            "serviceId" => "#{asr_service_id}",
            "audioFormat" => "flac",
            "samplingRate" => 16000
          }
        }
      ],
      "inputData" => %{
        "audio" => [
          %{
            "audioContent" => "#{base64_data}"
          }
        ]
      }
    }

    case Tesla.post(callback_url, Jason.encode!(asr_post_body), headers: asr_headers) do
      {:ok, %Tesla.Env{status: 200, body: asr_response_body}} ->
        # Handle the new API response with status code 200
        Jason.decode!(asr_response_body)
        decoded_response = Jason.decode!(asr_response_body)
        output_value = get_output_from_response(decoded_response)
        %{success: true, asr_response_text: output_value}

      {:ok, %Tesla.Env{status: status_code, body: asr_response_body}} ->
        %{success: false, asr_response_text: status_code}

      {:error, %Tesla.Env{status: status_code, body: error_reason}} ->
        %{success: false, asr_response_text: error_reason}

      {:error, reason} ->
        %{success: false, asr_response_text: reason}
    end
  end

  defp get_output_from_response(decoded_response) do
    case decoded_response["pipelineResponse"] do
      [%{"output" => [%{"source" => source}]} | _rest] ->
        source

      _ ->
        nil
    end
  end

  # Make the API call using Tesla
  def with_config_request(
        speech,
        user_id,
        ulca_apikey,
        pipeline_id,
        source_language,
        base_url
      ) do
    {:ok, response} = get(speech)

    content = Base.encode64(response.body)

    default_headers = [
      {"userID", "#{user_id}"},
      {"ulcaApiKey", "#{ulca_apikey}"},
      {"Content-Type", "application/json"}
    ]

    post_body = %{
      "pipelineTasks" => [
        %{
          "taskType" => "asr",
          "config" => %{
            "language" => %{
              "sourceLanguage" => "#{source_language}"
            }
          }
        }
      ],
      "pipelineRequestConfig" => %{
        "pipelineId" => "#{pipeline_id}"
      }
    }

    case Tesla.post("#{base_url}getModelsPipeline", Jason.encode!(post_body),
           headers: default_headers
         ) do
      {:ok, response} ->
        case response.status do
          200 ->
            response.body
            # Extract necessary data from the response
            decoded_response = Jason.decode!(response.body)

            callback_url =
              Map.get(decoded_response, "pipelineInferenceAPIEndPoint")["callbackUrl"]

            inference_api_key =
              Map.get(decoded_response, "pipelineInferenceAPIEndPoint")["inferenceApiKey"]

            authorization_key = Map.get(inference_api_key, "name")
            authorization_value = Map.get(inference_api_key, "value")

            asr_service_id =
              case Map.get(decoded_response, "pipelineResponseConfig") do
                [%{"config" => [%{"serviceId" => service_id}]}] -> service_id
                _ -> nil
              end

            source_language =
              case Map.get(decoded_response, "languages") do
                [%{"sourceLanguage" => source_language}] -> source_language
                _ -> nil
              end

            make_asr_api_call(
              authorization_key,
              authorization_value,
              callback_url,
              asr_service_id,
              source_language,
              content
            )

          code ->
            # Handle other successful responses with non-200 status codes
            IO.puts("API call returned status code: #{code}")
            IO.puts(response.body)
        end

      {:error, reason} ->
        # Handle errors
        IO.puts("API call failed with reason: #{inspect(reason)}")
    end
  end
end
