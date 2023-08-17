defmodule Glific.ASR.Bhasini do
  @moduledoc """
  This is a module to convert speech to text by using bhasini api
  """
  use Tesla

  @doc """
  Performs an ASR (Automatic Speech Recognition) API call with configuration request.

  This function makes an API call to the Bhasini ASR service using the provided configuration parameters and returns the ASR response text.
  """
  @spec with_config_request(map(), String.t()) :: map()
  def with_config_request(fields, source_language) do
    {:ok, response} = get(fields["speech"])

    content = Base.encode64(response.body)

    default_headers = [
      {"userID", "#{fields["userID"]}"},
      {"ulcaApiKey", "#{fields["ulcaApiKey"]}"},
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
        "pipelineId" => "#{fields["pipelineId"]}"
      }
    }

    case Tesla.post("#{fields["base_url"]}getModelsPipeline", Jason.encode!(post_body),
           headers: default_headers,
           opts: [adapter: [recv_timeout: 300_000]]
         ) do
      {:ok, response} ->
        handle_response(response, content)

      {:error, reason} ->
        %{
          success: false,
          msg: "API call failed with reason: #{reason}"
        }
    end
  end

  @spec make_asr_api_call(
          authorization_key :: String.t(),
          authorization_value :: String.t(),
          callback_url :: String.t(),
          asr_service_id :: String.t(),
          source_language :: String.t(),
          base64_data :: String.t()
        ) :: %{
          success: boolean(),
          asr_response_text: String.t() | integer()
        }
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
            "samplingRate" => 16_000
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

    case Tesla.post(callback_url, Jason.encode!(asr_post_body), headers: asr_headers, opts: [adapter: [recv_timeout: 300_000]]) do
      {:ok, %Tesla.Env{status: 200, body: asr_response_body}} ->
        # Handle the new API response with status code 200
        Jason.decode!(asr_response_body)
        decoded_response = Jason.decode!(asr_response_body)
        output_value = get_output_from_response(decoded_response)
        %{success: true, asr_response_text: output_value}

      {:ok, %Tesla.Env{status: status_code}} ->
        %{success: false, asr_response_text: status_code}

      {:error, %Tesla.Env{body: error_reason}} ->
        %{success: false, asr_response_text: error_reason}

      {:error, reason} ->
        %{success: false, asr_response_text: reason}
    end
  end

  @spec get_output_from_response(decoded_response :: map()) :: String.t() | nil
  defp get_output_from_response(decoded_response) do
    case decoded_response["pipelineResponse"] do
      [%{"output" => [%{"source" => source}]} | _rest] ->
        source

      _ ->
        nil
    end
  end

  @spec handle_response(map(), String.t()) :: map()
  defp handle_response(%{status: 200} = response, content) do
    # Extract necessary data from the response
    decoded_response = Jason.decode!(response.body)

    callback_url = Map.get(decoded_response, "pipelineInferenceAPIEndPoint")["callbackUrl"]

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
  end

  defp handle_response(%{status: status_code} = _response, _content) do
    %{
      success: false,
      msg: "API call returned status code: #{status_code}"
    }
  end
end
