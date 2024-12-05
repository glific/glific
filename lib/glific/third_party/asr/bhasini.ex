defmodule Glific.ASR.Bhasini do
  @moduledoc """
  This is a module to convert speech to text by using Bhasini API
  """
  use Tesla
  require Logger

  alias Glific.Contacts

  @config_url "https://meity-auth.ulcacontrib.org/ulca/apis/v0/model"
  @meity_pipeline_id "64392f96daac500b55c543cd"
  @language_detect_url "https://dhruva-api.bhashini.gov.in/services/inference/audiolangdetection"
  # @ai4bharat_pipeline_id "643930aa521a4b1ba0f4c41d"

  @doc """
  Validate audio url
  """
  @spec validate_audio(String.t()) :: true | String.t()
  def validate_audio(url),
    do: if(String.starts_with?(url, "https"), do: true, else: "Media URL is invalid")

  @doc """
  Validate speech to text params
  """
  @spec validate_params(map()) :: {:ok, any()} | {:error, String.t()}
  def validate_params(fields) do
    with true <- Map.has_key?(fields, "contact"),
         true <- Map.has_key?(fields, "speech"),
         true <- validate_audio(fields["speech"]) do
      fields["contact"]["id"]
      |> Glific.parse_maybe_integer!()
      |> Contacts.preload_contact_language()
      |> then(&{:ok, &1})
    else
      false ->
        {:error, "Missing required parameters: contact or speech"}

      error ->
        {:error, error}
    end
  end

  @doc """
  Detects a language
  """
  @spec detect_language(String.t()) :: map()
  def detect_language(url) do
    bhasini_keys = Glific.get_bhasini_keys()

    payload = %{
      "config" => %{"serviceId" => "bhashini/iitmandi/audio-lang-detection/gpu"},
      "audio" => [%{"audioUri" => url}]
    }

    case Tesla.post(@language_detect_url, Jason.encode!(payload),
           headers: [
             {"Authorization", bhasini_keys.inference_key},
             {"Content-Type", "application/json"}
           ],
           opts: [adapter: [recv_timeout: 300_000]]
         ) do
      {:ok, %Tesla.Env{status: 200, body: asr_response_body}} ->
        # Handle the new API response with status code 200
        decoded_response = Jason.decode!(asr_response_body)

        detected_language_code =
          get_in(decoded_response, [
            "output",
            Access.at(0),
            "langPrediction",
            Access.at(0),
            "langCode"
          ])

        language = Glific.Settings.get_language_by_label_or_locale(detected_language_code)

        %{success: true, detected_language: get_in(language, [Access.at(0), "label"])}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.info(
          "Invalid status received from Bhashini while detecting language for url: #{url} status: #{status}  body: #{body}"
        )

        %{success: false, detected_language: "Could not detect language"}

      {:error, reason} ->
        Logger.info(
          "Invalid status received from Bhashini while detecting language for url: #{url} reason: #{reason}"
        )

        %{success: false, detected_language: "Could not detect language"}
    end
  end

  @doc """
  Performs an ASR (Automatic Speech Recognition) API call with configuration request.

  This function makes an API call to the Bhasini ASR service using the provided configuration parameters and returns the ASR response text.
  """
  @spec with_config_request(Keyword.t()) :: {:ok, map()} | map()
  def with_config_request(params) do
    source_language = Keyword.get(params, :source_language)
    target_language = Keyword.get(params, :target_language)
    task_type = Keyword.get(params, :task_type)
    bhasini_keys = Glific.get_bhasini_keys()

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

        {:error, "API call failed with reason: #{reason}"}
    end
  end

  @spec get_config_request_body(String.t(), String.t(), String.t()) :: map()
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
              "sourceLanguage" => Glific.Bhasini.get_iso_code(source_language, "iso_639_1")
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
            "samplingRate" => 16_000,
            "preProcessors" => ["vad"],
            "postProcessors" => ["punctuation"]
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
