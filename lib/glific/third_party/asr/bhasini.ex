defmodule Glific.ASR.Bhasini do
  @moduledoc """
  This is a module to convert speech to text by using bhasini api
  """
  use Tesla
  require Logger

  @config_url "https://meity-auth.ulcacontrib.org/ulca/apis/v0/model"
  @meity_pipeline_id "64392f96daac500b55c543cd"
  # @ai4bharat_pipeline_id "643930aa521a4b1ba0f4c41d"

  @doc """
  Performs an ASR (Automatic Speech Recognition) API call with configuration request.

  This function makes an API call to the Bhasini ASR service using the provided configuration parameters and returns the ASR response text.
  """
  @spec with_config_request(map(), String.t()) :: {:ok, map()} | map()
  def with_config_request(fields, source_language, target_language \\ "") do
    bhasini_keys = Glific.get_bhasini_keys()
    task_type = fields["task_type"] || "asr"

    default_headers = [
      {"userID", bhasini_keys.user_id},
      {"ulcaApiKey", bhasini_keys.ulca_api_key},
      {"Content-Type", "application/json"}
    ]

    post_body = get_config_request_body(task_type, source_language, target_language)

    url = @config_url <> "/getModelsPipeline"

    case Tesla.post(url, Jason.encode!(post_body),
           headers: default_headers,
           opts: [adapter: [recv_timeout: 300_000]]
         ) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        Logger.error("API call failed with reason:  #{reason}")

        %{
          success: false,
          msg: "API call failed with reason: #{reason}"
        }
    end
  end

  defp get_config_request_body("nmt_tts", source_language, target_language) do
    %{
      "pipelineTasks" => [
        %{
          "taskType" => "translation",
          "config" => %{
            "language" => %{
              "sourceLanguage" => "#{source_language}",
              "targetLanguage" => "#{target_language}"
            }
          }
        },
        %{
          "taskType" => "tts",
          "config" => %{
            "language" => %{
              "sourceLanguage" => "#{source_language}"
            }
          }
        }
      ],
      "pipelineRequestConfig" => %{
        "pipelineId" => @meity_pipeline_id
      }
    }
  end

  defp get_config_request_body(task_type, source_language, _target_language) do
    %{
      "pipelineTasks" => [
        %{
          "taskType" => task_type,
          "config" => %{
            "language" => %{
              "sourceLanguage" => "#{source_language}"
            }
          }
        }
      ],
      "pipelineRequestConfig" => %{
        "pipelineId" => @meity_pipeline_id
      }
    }
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

    case Tesla.post(callback_url, Jason.encode!(asr_post_body),
           headers: asr_headers,
           opts: [adapter: [recv_timeout: 300_000]]
         ) do
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

  @doc """
  Subsequent API call to Bhasini for ASR after config call
  """
  @spec handle_response(map(), String.t()) :: map()
  def handle_response(%{status: 200} = response, content) do
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

  def handle_response(response, _content) do
    Logger.error("Bhasini API call failed: #{response}")

    %{
      success: false,
      msg: "API call to Bhasini failed"
    }
  end
end
