defmodule Glific.ThirdParty.Kaapi do
  @moduledoc """
  Kaapi is our own internal services that handles all AI related features.
  """
  require Logger

  import Glific.SafeLog

  alias Glific.Caches
  alias Glific.Partners
  alias Glific.Partners.Credential
  alias Glific.Providers.Gupshup.ApiClient, as: GupshupClient
  alias Glific.ThirdParty.Kaapi.ApiClient

  # Update all Error struct data in this format
  defmodule Error do
    @moduledoc """
    Custom error module for Kaapi API failures.
    Since Kaapi is a backend service (NGOs don’t interact with it directly),
    sending errors to them won’t resolve the issue.
    Reporting these failures to AppSignal lets us detect and fix problems
    """
    defexception [:message, :reason, :organization_id]

    @spec message(%__MODULE__{}) :: String.t()
    def message(%Error{} = error) do
      "#{error.message} reason: #{error.reason} organization_id: #{error.organization_id}"
    end
  end

  @doc """
  Fetch the kaapi creds
  """
  @spec fetch_kaapi_creds(non_neg_integer) :: nil | {:ok, any} | {:error, any}
  def fetch_kaapi_creds(organization_id) do
    organization = Partners.organization(organization_id)

    organization.services["kaapi"]
    |> case do
      nil ->
        {:error, "Kaapi is not active"}

      credentials ->
        {:ok, credentials.secrets}
    end
  end

  @doc """
  Onboard an organization to Kaapi.
  """
  @spec onboard(map()) :: {:ok | :error, binary()}
  def onboard(params) do
    with {:ok, %{data: %{api_key: api_key}}} <- ApiClient.onboard_to_kaapi(params),
         {:ok, _} <- insert_kaapi_provider(params.organization_id, api_key) do
      Logger.info("KAAPI onboarding success for org: #{params.organization_id}")

      {:ok, "KAAPI onboarding successful for org #{params.organization_id}"}
    else
      {:error, error} ->
        Glific.log_exception(%Error{
          message:
            "Kaapi onboarding failed for org_id=#{params.organization_id}, reason=#{safe_inspect(error)}"
        })

        {:error,
         "KAAPI onboarding failed for org #{params.organization_id}: #{safe_inspect(error)}"}
    end
  end

  @doc """
  Update an existing Kaapi project with the Google API key.
  """
  @spec update_google_api_key(non_neg_integer()) :: {:ok, String.t()} | {:error, String.t()}
  def update_google_api_key(organization_id) do
    update_provider_credential(
      organization_id,
      "google",
      %{google: %{api_key: Glific.get_google_api_key()}}
    )
  end

  @doc """
  Update an existing Kaapi project with the OpenAI API key.
  """
  @spec update_openai_api_key(non_neg_integer()) :: {:ok, String.t()} | {:error, String.t()}
  def update_openai_api_key(organization_id) do
    update_provider_credential(
      organization_id,
      "openai",
      %{openai: %{api_key: Glific.get_open_ai_key()}}
    )
  end

  @spec update_provider_credential(non_neg_integer(), String.t(), map()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp update_provider_credential(organization_id, provider, credential) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, _} <-
           ApiClient.update_organization_credentials(
             %{provider: provider, credential: credential, is_active: true},
             secrets["api_key"]
           ) do
      Logger.info("KAAPI #{provider} credential update success for org: #{organization_id}")
      {:ok, "KAAPI #{provider} credential updated for org #{organization_id}"}
    else
      {:error, error} ->
        Glific.log_exception(%Error{
          message:
            "KAAPI #{provider} credential update failed for org_id=#{organization_id}, reason=#{safe_inspect(error)}"
        })

        {:error,
         "KAAPI #{provider} credential update failed for org #{organization_id}: #{safe_inspect(error)}"}
    end
  end

  @doc """
  Ingest an AI assistant to Kaapi
  """
  @spec ingest_ai_assistant(non_neg_integer(), binary()) :: {:ok, map()} | {:error, any()}
  def ingest_ai_assistant(organization_id, assistant_id) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <-
           ApiClient.ingest_ai_assistants(secrets["api_key"], assistant_id) do
      Logger.info(
        "KAAPI ingest successful for org: #{organization_id}, assistant: #{assistant_id}"
      )

      {:ok, result}
    else
      {:error, reason} ->
        Glific.log_exception(%Error{
          message:
            "Assistant import failed in kaapi: organization_id=#{organization_id}, assistant_id=#{assistant_id}, reason=#{safe_inspect(reason)}"
        })

        {:error, reason}
    end
  end

  @doc """
  Create a config in Kaapi for the assistant
  """
  @spec create_assistant_config(map(), non_neg_integer()) ::
          {:ok, map()} | {:error, map() | binary()}
  def create_assistant_config(params, organization_id) do
    config_blob = build_config_blob(params, params.knowledge_base_ids, organization_id)

    body = %{
      name: params.name,
      commit_message: params[:description] || "",
      config_blob: config_blob
    }

    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <- ApiClient.create_config(body, secrets["api_key"]) do
      Logger.info(
        "Kaapi Config creation successful for org: #{organization_id}, name: #{params.name}"
      )

      {:ok, result}
    else
      {:error, reason} ->
        Appsignal.send_error(
          %Error{
            message: "Kaapi Config creation failed for name #{params.name}",
            organization_id: organization_id,
            reason: safe_inspect(reason)
          },
          []
        )

        {:error, reason}
    end
  end

  @doc """
  Create a new version of an config in Kaapi, send error to Appsignal if failed.
  """
  @spec create_config_version(binary(), map(), non_neg_integer()) ::
          {:ok, map()} | {:error, map() | binary()}
  def create_config_version(config_id, params, organization_id) do
    config_blob = build_config_blob(params, params.knowledge_base_ids, organization_id)

    body = %{
      commit_message: params[:description] || "",
      config_blob: config_blob
    }

    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <- ApiClient.create_config_version(config_id, body, secrets["api_key"]) do
      Logger.info(
        "Kaapi Config Version creation successful for org: #{organization_id}, Config ID: #{config_id}"
      )

      {:ok, result}
    else
      {:error, reason} ->
        Appsignal.send_error(
          %Error{
            message: "Kaapi Config Version creation failed for Config ID #{config_id}",
            organization_id: organization_id,
            reason: safe_inspect(reason)
          },
          []
        )

        {:error, reason}
    end
  end

  @doc """
  Update an AI assistant in Kaapi, send error to Appsignal if failed.
  """
  @spec update_assistant(map(), non_neg_integer()) :: {:ok, map()} | {:error, map() | binary()}
  def update_assistant(%{id: assistant_id} = params, organization_id) do
    params = %{
      name: params.name,
      model: params.model,
      instructions: params.instructions,
      temperature: params.temperature,
      organization_id: organization_id,
      vector_store_ids_add:
        get_in(params, [:tool_resources, :file_search, :vector_store_ids]) || []
    }

    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <-
           ApiClient.update_assistant(assistant_id, params, secrets["api_key"]) do
      Logger.info(
        "KAAPI AI Assistant update successful for org: #{organization_id}, assistant: #{assistant_id}"
      )

      {:ok, result}
    else
      {:error, reason} ->
        Appsignal.send_error(
          %Error{
            message: "Kaapi AI Assistant update failed for assistant_id=#{assistant_id}",
            organization_id: organization_id,
            reason: safe_inspect(reason)
          },
          []
        )

        {:error, reason}
    end
  end

  @doc """
  Delete an assistant in Kaapi, send error to Appsignal if failed.
  """
  @spec delete_assistant(binary(), non_neg_integer()) :: {:ok, map()} | {:error, map() | binary()}
  def delete_assistant(assistant_id, organization_id) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <-
           ApiClient.delete_assistant(assistant_id, secrets["api_key"]) do
      Logger.info("KAAPI AI Assistant delete successful for, assistant: #{assistant_id}")

      {:ok, result}
    else
      {:error, reason} ->
        Glific.log_exception(%Error{
          message: "Kaapi AI Assistant delete failed for assistant_id=#{assistant_id}",
          organization_id: organization_id,
          reason: safe_inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Create a collection (Knowledge Base in Glific) in Kaapi and send error to Appsignal if failed
  """
  @spec create_collection(map(), non_neg_integer()) :: {:ok, map()} | {:error, map() | String.t()}
  def create_collection(params, organization_id) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <- ApiClient.create_collection(params, secrets["api_key"]) do
      Logger.info(
        "Kaapi Knowledge Base creation job successfully created for org: #{organization_id}"
      )

      {:ok, result}
    else
      {:error, reason} ->
        Glific.log_exception(%Error{
          message: "Failed to create Kaapi Knowledge Base creation job",
          organization_id: organization_id,
          reason: safe_inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Gets the status of a collection creation job in Kaapi.
  """
  @spec get_collection_status(String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, any()}
  def get_collection_status(collection_job_id, organization_id) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, %{data: data}} <-
           ApiClient.get_collection_status(collection_job_id, secrets["api_key"]) do
      {:ok, data}
    else
      {:error, reason} ->
        Appsignal.send_error(
          %Error{
            message: "Failed to get Kaapi collection status",
            organization_id: organization_id,
            reason: safe_inspect(reason)
          },
          []
        )

        {:error, reason}
    end
  end

  @spec build_config_blob(map(), list(String.t()), non_neg_integer()) :: map()
  defp build_config_blob(params, knowledge_base_ids, organization_id) do
    model = params.model || "gpt-4o"

    base_params = %{
      "model" => model,
      "instructions" => params.prompt || "You are a helpful assistant",
      "knowledge_base_ids" => knowledge_base_ids
    }

    completion_params =
      (params[:settings] || %{})
      |> stringify_keys()
      |> put_default_tunable_param(model, organization_id)
      |> Map.merge(base_params)

    %{
      completion: %{
        type: "text",
        provider: params[:provider] || "openai",
        params: completion_params
      }
    }
  end

  # Default comes from the model's own Kaapi config
  @spec put_default_tunable_param(map(), String.t(), non_neg_integer()) :: map()
  defp put_default_tunable_param(settings, _model, _organization_id)
       when is_map_key(settings, "temperature") or is_map_key(settings, "effort"),
       do: settings

  # Set default temperature as 1 for models that support it, or effort as "low" for models that support it.
  defp put_default_tunable_param(settings, model, organization_id) do
    with {:ok, models} <- list_models(organization_id),
         %{config: config} <- Enum.find(models, &(&1.model_name == model)) do
      cond do
        is_map_key(config, :effort) -> Map.put(settings, "effort", "low")
        is_map_key(config, :temperature) -> Map.put(settings, "temperature", 1)
        true -> settings
      end
    else
      _ -> settings
    end
  end

  @spec stringify_keys(map()) :: map()
  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  # Error type strings surfaced in webhook logs and flow failure path.
  # Each string is checked as a substring of the Kaapi error message body.
  @kaapi_error_types ~w(transcription_failed unsupported_format duration_exceeded rate_limited timeout service_unavailable invalid_request)

  @doc """
  Initiates async Speech-to-Text via Kaapi unified LLM API.

  Downloads audio from `audio_url`, encodes it as base64, and calls Kaapi.
  Kaapi will POST the result to `callback_url` with `request_metadata` echoed back
  so the flow can be resumed. Returns `%{success: true}` on successful initiation.

  Optional `opts` map keys: `provider`, `model`, `language` — override defaults when provided.
  """
  @spec speech_to_text(String.t(), String.t(), map(), non_neg_integer(), map()) :: map()
  def speech_to_text(audio_url, callback_url, request_metadata, organization_id, opts \\ %{}) do
    with {:ok, encoded_audio, _content_type} <-
           GupshupClient.download_media_content(audio_url, organization_id),
         {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         payload = stt_payload(encoded_audio, callback_url, request_metadata, opts),
         {:ok, body} <- ApiClient.call_llm(payload, secrets["api_key"]) do
      normalize_kaapi_body(body)
    else
      {:error, :download_failed} ->
        %{success: false, error_type: "download_failed", reason: "Audio file download failed"}

      error ->
        handle_kaapi_error(error, organization_id, "STT", "transcription_failed")
    end
  end

  @doc """
  Initiates async Text-to-Speech via Kaapi unified LLM API.

  Calls Kaapi which will POST the result to `callback_url` with `request_metadata`
  echoed back so the flow can be resumed. Returns `%{success: true}` on initiation.

  Optional `opts` map keys: `provider`, `model`, `language`, `voice` — override defaults when provided.
  """
  @spec text_to_speech(non_neg_integer(), String.t(), String.t(), map(), map()) :: map()
  def text_to_speech(organization_id, text, callback_url, request_metadata, opts \\ %{}) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         payload = tts_payload(text, callback_url, request_metadata, opts),
         {:ok, body} <- ApiClient.call_llm(payload, secrets["api_key"]) do
      normalize_kaapi_body(body)
    else
      error ->
        handle_kaapi_error(error, organization_id, "TTS", "service_unavailable")
    end
  end

  @doc """
  Sends an ad-hoc `PromptGenerator` payload for async LLM prompt generation via Kaapi.
  """
  @spec generate_prompt(map(), non_neg_integer()) ::
          {:ok, %{job_id: String.t(), conversation_id: String.t() | nil}} | {:error, any()}
  def generate_prompt(payload, organization_id),
    do: dispatch_llm_job(payload, organization_id, "generate_prompt")

  @doc """
  Sends a stored-config (`config: %{id:, version:}`) Kaapi LLM call, e.g. the
  "Try It Out" chat sandbox. Distinct from `generate_prompt/2` so the two payload shapes
  are never confused.
  """
  @spec llm_call(map(), non_neg_integer()) ::
          {:ok, %{job_id: String.t(), conversation_id: String.t() | nil}} | {:error, any()}
  def llm_call(payload, organization_id) do
    dispatch_llm_job(payload, organization_id, "llm_call")
  end

  @spec dispatch_llm_job(map(), non_neg_integer(), String.t()) ::
          {:ok, %{job_id: String.t(), conversation_id: String.t() | nil}} | {:error, any()}
  defp dispatch_llm_job(payload, organization_id, caller) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, body} <- ApiClient.call_llm(payload, secrets["api_key"]),
         %{data: %{job_id: job_id} = data} when is_binary(job_id) <- body do
      {:ok, %{job_id: job_id, conversation_id: get_in(data, [:conversation, :id])}}
    else
      {:error, %{status: status, body: %{success: false} = body}} ->
        message = extract_error_message(body)

        Glific.log_error(
          "Kaapi #{caller} rejected request for org_id=#{organization_id}, status=#{status}, reason=#{message}"
        )

        {:error, message}

      {:error, reason} ->
        Glific.log_exception(%Error{
          message:
            "Kaapi #{caller} failed for org_id=#{organization_id}, reason=#{safe_inspect(reason)}"
        })

        {:error, safe_inspect(reason)}

      other ->
        Glific.log_exception(%Error{
          message:
            "Kaapi #{caller} returned unexpected body for org_id=#{organization_id}, body=#{safe_inspect(other)}"
        })

        {:error, "Unexpected Kaapi response: #{safe_inspect(other)}"}
    end
  end

  @doc """
  Converts a Kaapi 2xx async-dispatch body into the standard webhook result
  """
  @spec normalize_kaapi_body(any()) :: map()
  def normalize_kaapi_body(body) when is_map(body) do
    case body do
      %{success: false} -> logical_failure(body[:message] || body[:error])
      _ -> Map.merge(%{success: true}, body)
    end
  end

  def normalize_kaapi_body(_body),
    do: %{success: false, error_type: "kaapi_logical_failure", reason: "Unexpected response"}

  @spec logical_failure(String.t() | nil) :: map()
  defp logical_failure(reason) do
    %{
      success: false,
      http_status: 200,
      error_type: "kaapi_logical_failure",
      reason: reason || "Kaapi logical failure"
    }
  end

  @spec handle_kaapi_error(tuple(), non_neg_integer(), String.t(), String.t()) :: map()
  defp handle_kaapi_error({:error, %{status: 429}}, _org_id, _label, _fallback),
    do: %{
      success: false,
      error_type: "rate_limited",
      reason: "Rate limit exceeded",
      http_status: 429
    }

  defp handle_kaapi_error({:error, %{status: 408}}, _org_id, _label, _fallback),
    do: %{
      success: false,
      error_type: "timeout",
      reason: "Request timed out",
      http_status: 408
    }

  defp handle_kaapi_error({:error, :timeout}, _org_id, _label, _fallback),
    do: %{
      success: false,
      error_type: "request_timeout",
      reason: "Request timed out (recv_timeout exceeded)",
      http_status: nil
    }

  defp handle_kaapi_error({:error, %{status: status, body: body}}, _org_id, _label, _fallback)
       when status in 400..499,
       do: %{
         success: false,
         error_type: "invalid_request",
         reason: extract_error_message(body),
         http_status: status
       }

  defp handle_kaapi_error({:error, %{status: status, body: body}}, _org_id, _label, _fallback)
       when status in 500..599,
       do: %{
         success: false,
         error_type: "service_unavailable",
         reason: extract_error_message(body),
         http_status: status
       }

  defp handle_kaapi_error({:error, %{status: status, body: body}}, _org_id, _label, _fallback),
    do: %{
      success: false,
      error_type: classify_error(body),
      reason: extract_error_message(body),
      http_status: status
    }

  defp handle_kaapi_error({:error, reason}, organization_id, label, fallback_type) do
    Glific.log_exception(%Error{
      message:
        "Kaapi #{label} failed for org_id=#{organization_id}, reason=#{safe_inspect(reason)}"
    })

    %{
      success: false,
      error_type: fallback_type,
      reason: safe_inspect(reason),
      http_status: nil
    }
  end

  @spec extract_error_message(map() | any()) :: String.t()
  # when payload has a list of field-level errors
  # {"error":"Validation failed","errors":[{"field":"config.id","message":"Input should be a valid UUID..."}]}
  defp extract_error_message(%{errors: errors}) when is_list(errors) and errors != [] do
    Enum.map_join(errors, "; ", &"#{&1[:field]}: #{&1[:message]}")
  end

  defp extract_error_message(body) when is_map(body),
    do: body[:error] || body[:message] || safe_inspect(body)

  defp extract_error_message(body), do: safe_inspect(body)

  @spec classify_error(map() | any()) :: String.t()
  defp classify_error(body) do
    message = body |> extract_error_message() |> String.downcase()
    Enum.find(@kaapi_error_types, "transcription_failed", &String.contains?(message, &1))
  end

  @spec model_config(atom()) :: String.t()
  defp model_config(key), do: Application.fetch_env!(:glific, __MODULE__)[key]

  @spec stt_payload(String.t(), String.t(), map(), map()) :: map()
  defp stt_payload(encoded_audio, callback_url, request_metadata, opts) do
    base_params = %{
      model: opts[:model] || model_config(:stt_model),
      input_language: opts[:language] || "auto"
    }

    output_language = opts[:output_language]

    params =
      if is_binary(output_language) and String.trim(output_language) != "" do
        Map.put(base_params, :output_language, output_language)
      else
        base_params
      end

    %{
      query: %{
        input: %{
          type: "audio",
          content: %{format: "base64", value: encoded_audio, mime_type: "audio/wav"}
        }
      },
      config: %{
        blob: %{
          completion: %{
            provider: opts[:provider] || "google",
            type: "stt",
            params: params
          }
        }
      },
      callback_url: callback_url,
      request_metadata: request_metadata
    }
  end

  @spec tts_payload(String.t(), String.t(), map(), map()) :: map()
  defp tts_payload(text, callback_url, request_metadata, opts) do
    %{
      query: %{input: text},
      config: %{
        blob: %{
          completion: %{
            provider: opts[:provider] || "google",
            type: "tts",
            params: %{
              model: opts[:model] || model_config(:tts_model),
              voice: opts[:voice] || "Kore",
              language: opts[:language] || "hindi",
              response_format: "mp3"
            }
          }
        }
      },
      callback_url: callback_url,
      request_metadata: request_metadata
    }
  end

  @doc """
  Upload a document to Kaapi documents API, send error to Appsignal if failed.
  """
  @spec upload_document(map(), non_neg_integer()) :: {:ok, map()} | {:error, map() | binary()}
  def upload_document(params, organization_id) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <-
           ApiClient.upload_document(params, secrets["api_key"]) do
      Logger.info("KAAPI document upload successful for, file: #{params.filename}")

      {:ok, result}
    else
      {:error, reason} ->
        Appsignal.send_error(
          %Error{
            message: "Kaapi document upload failed for, filename=#{params.filename}",
            reason: safe_inspect(reason),
            organization_id: organization_id
          },
          []
        )

        {:error, reason}
    end
  end

  @doc """
  Delete a config and all associated versions in Kaapi, send error to Appsignal if failed.
  """
  @spec delete_config(binary(), non_neg_integer()) :: {:ok, map()} | {:error, map() | binary()}
  def delete_config(uuid, organization_id) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <-
           ApiClient.delete_config(uuid, secrets["api_key"]) do
      Logger.info("KAAPI config delete successful for org: #{organization_id}, config: #{uuid}")

      {:ok, result}
    else
      {:error, reason} ->
        Appsignal.send_error(
          %Error{
            message: "KAAPI config delete failed for config=#{uuid}",
            organization_id: organization_id,
            reason: safe_inspect(reason)
          },
          []
        )

        {:error, reason}
    end
  end

  @doc """
  Create an evaluation on Kaapi.
  """
  @spec create_evaluation(map(), non_neg_integer()) :: {:ok, map()} | {:error, any()}
  def create_evaluation(params, organization_id) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <- ApiClient.create_evaluation(params, secrets["api_key"]) do
      {:ok, result}
    else
      {:error, reason} ->
        Glific.log_exception(%Error{
          message:
            "Kaapi evaluation creation failed: evaluation_name=#{params[:experiment_name]}",
          organization_id: organization_id,
          reason: safe_inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Create an evaluation on Kaapi via the v2 endpoint.
  """
  @spec create_evaluation_v2(map(), non_neg_integer()) :: {:ok, map()} | {:error, any()}
  def create_evaluation_v2(params, organization_id) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <- ApiClient.create_evaluation_v2(params, secrets["api_key"]) do
      {:ok, result}
    else
      {:error, reason} ->
        Glific.log_exception(%Error{
          message:
            "Kaapi evaluation v2 creation failed: evaluation_name=#{params[:experiment_name]}",
          organization_id: organization_id,
          reason: safe_inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Get full scores for a completed evaluation from Kaapi (includes all evaluators via Langfuse).
  """
  @spec get_evaluation_scores(non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, any()}
  def get_evaluation_scores(evaluation_id, organization_id) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <- ApiClient.get_evaluation_scores(evaluation_id, secrets["api_key"]) do
      {:ok, result}
    else
      {:error, :timeout} ->
        Logger.error("Kaapi timeout fetching evaluation scores: evaluation_id=#{evaluation_id}")

        {:error, :timeout}

      {:error, reason} ->
        Glific.log_exception(%Error{
          message: "Kaapi evaluation scores fetch failed: evaluation_id=#{evaluation_id}",
          organization_id: organization_id,
          reason: safe_inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Request a v2 prompt-improvement recommendation from Kaapi for a completed evaluation.
  """
  @spec improve_evaluation_prompt(non_neg_integer(), String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, any()}
  def improve_evaluation_prompt(kaapi_evaluation_id, callback_url, organization_id) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, %{data: data}} <-
           ApiClient.improve_prompt_v2(
             kaapi_evaluation_id,
             %{callback_url: callback_url},
             secrets["api_key"]
           ) do
      {:ok, data}
    else
      {:error, reason} ->
        Glific.log_exception(%Error{
          message:
            "Kaapi improve_evaluation_prompt failed for kaapi_evaluation_id=#{kaapi_evaluation_id}",
          organization_id: organization_id,
          reason: safe_inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Get dataset details from Kaapi with optional signed URL.
  """
  @spec get_dataset(non_neg_integer(), non_neg_integer(), boolean()) ::
          {:ok, map()} | {:error, any()}
  def get_dataset(dataset_id, organization_id, include_signed_url \\ false) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, %{success: true, data: data}} <-
           ApiClient.get_dataset(dataset_id, secrets["api_key"], include_signed_url) do
      if include_signed_url && !Map.has_key?(data, :signed_url) do
        Glific.log_exception(%Error{
          message: "Kaapi dataset response missing signed_url",
          organization_id: organization_id,
          reason: safe_inspect(data)
        })

        {:error, "Dataset download URL not available"}
      else
        {:ok, data}
      end
    else
      {:error, reason} ->
        Glific.log_exception(%Error{
          message: "Failed to get dataset from Kaapi",
          organization_id: organization_id,
          reason: safe_inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Get document details from Kaapi, including its signed download URL.
  """
  @spec get_document(String.t(), non_neg_integer()) :: {:ok, map()} | {:error, any()}
  def get_document(document_id, organization_id) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, body} <- ApiClient.get_document(document_id, secrets["api_key"]) do
      validate_document_response(body, organization_id)
    else
      {:error, reason} ->
        Glific.log_exception(%Error{
          message: "Failed to get document from Kaapi",
          organization_id: organization_id,
          reason: safe_inspect(reason)
        })

        {:error, reason}
    end
  end

  @spec validate_document_response(any(), non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  defp validate_document_response(
         %{success: true, data: %{signed_url: signed_url}} = body,
         _organization_id
       )
       when is_binary(signed_url) and signed_url != "" do
    %{data: data} = body
    {:ok, data}
  end

  defp validate_document_response(body, organization_id) do
    Glific.log_exception(%Error{
      message: "Kaapi document response missing signed_url",
      organization_id: organization_id,
      reason: safe_inspect(body)
    })

    {:error, "File download URL not available"}
  end

  @doc """
  Delete an evaluation dataset from Kaapi.
  """
  @spec delete_evaluation_dataset(non_neg_integer() | String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, map() | binary()}
  def delete_evaluation_dataset(dataset_id, organization_id) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <- ApiClient.delete_evaluation_dataset(dataset_id, secrets["api_key"]) do
      Logger.info("Kaapi evaluation dataset delete successful for dataset: #{dataset_id}")

      {:ok, result}
    else
      {:error, reason} ->
        Glific.log_exception(%Error{
          message: "Failed to delete evaluation dataset from Kaapi",
          organization_id: organization_id,
          reason: safe_inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Upload an evaluation dataset to Kaapi, send error to Appsignal if failed.
  """
  @spec upload_evaluation_dataset(map(), non_neg_integer()) ::
          {:ok, map()} | {:error, map() | binary()} | {:error, :timeout}
  def upload_evaluation_dataset(params, organization_id) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <- ApiClient.upload_evaluation_dataset(params, secrets["api_key"]) do
      case result do
        %{data: %{dataset_name: dataset_name, dataset_id: dataset_id}} ->
          {:ok, %{name: dataset_name, dataset_id: dataset_id}}

        error ->
          Appsignal.send_error(
            %Error{
              message: "Got unexpected response from Kaapi while uploading evaluation dataset",
              organization_id: organization_id,
              reason: safe_inspect(error)
            },
            []
          )

          {:error, "An unknown error occurred, please contact Glific support."}
      end
    else
      {:error, reason} ->
        Appsignal.send_error(
          %Error{
            message: "Failed to upload evaluation dataset to Kaapi",
            organization_id: organization_id,
            reason: safe_inspect(reason)
          },
          []
        )

        {:error, reason}
    end
  end

  @doc """
  Upload an evaluation dataset to Kaapi via the v2 endpoint, send error to Appsignal if failed.
  """
  @spec upload_evaluation_dataset_v2(map(), non_neg_integer()) ::
          {:ok, map()} | {:error, map() | binary()} | {:error, :timeout}
  def upload_evaluation_dataset_v2(params, organization_id) do
    case fetch_kaapi_creds(organization_id) do
      {:ok, secrets} ->
        params
        |> ApiClient.upload_evaluation_dataset_v2(secrets["api_key"])
        |> handle_evaluation_dataset_v2_response(organization_id)

      {:error, reason} ->
        send_kaapi_error(
          "Failed to upload evaluation dataset v2 to Kaapi",
          organization_id,
          reason
        )

        {:error, reason}
    end
  end

  @models_cache_ttl_hours 6
  @models_provider "openai"

  @doc """
  List active Kaapi models for the (currently hardcoded) openai provider. Fetches all pages
  and caches the result globally for #{@models_cache_ttl_hours}h, since the model catalog is
  provider-wide, not org data.
  """
  @spec list_models(non_neg_integer()) :: {:ok, list(map())} | {:error, any()}
  def list_models(organization_id) do
    cache_key = {:kaapi_models, @models_provider}

    case Caches.get_global(cache_key) do
      {:ok, models} when is_list(models) ->
        {:ok, models}

      _ ->
        fetch_and_cache_models(organization_id, cache_key)
    end
  end

  @spec fetch_and_cache_models(non_neg_integer(), tuple()) :: {:ok, list(map())} | {:error, any()}
  defp fetch_and_cache_models(organization_id, cache_key) do
    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, models} <- fetch_all_models(secrets["api_key"]) do
      # avoid caching a transient empty result for @models_cache_ttl_hours
      if models != [], do: Caches.put_global(cache_key, models, @models_cache_ttl_hours)
      {:ok, models}
    else
      {:error, reason} ->
        Glific.log_exception(%Error{
          message:
            "Kaapi list_models failed for org_id=#{organization_id}, reason=#{safe_inspect(reason)}"
        })

        {:error, reason}
    end
  end

  @spec handle_evaluation_dataset_v2_response(
          {:ok, map()} | {:error, map() | binary() | :timeout},
          non_neg_integer()
        ) :: {:ok, map()} | {:error, map() | binary()}
  defp handle_evaluation_dataset_v2_response(
         {:ok, %{data: %{dataset_id: dataset_id, total_items: total_items}}},
         _organization_id
       ) do
    {:ok, %{dataset_id: dataset_id, total_items: total_items}}
  end

  defp handle_evaluation_dataset_v2_response({:error, reason}, organization_id) do
    send_kaapi_error("Failed to upload evaluation dataset v2 to Kaapi", organization_id, reason)
    {:error, reason}
  end

  defp handle_evaluation_dataset_v2_response({:ok, result}, organization_id) do
    send_kaapi_error(
      "Got unexpected response from Kaapi while uploading evaluation dataset v2",
      organization_id,
      result
    )

    {:error, "An unknown error occurred, please contact Glific support."}
  end

  @spec send_kaapi_error(String.t(), non_neg_integer(), term()) :: Appsignal.Span.t() | nil
  defp send_kaapi_error(message, organization_id, reason) do
    Appsignal.send_error(
      %Error{
        message: message,
        organization_id: organization_id,
        reason: safe_inspect(reason)
      },
      []
    )
  end

  @spec fetch_all_models(String.t()) :: {:ok, list(map())} | {:error, any()}
  defp fetch_all_models(api_key) do
    with {:ok, body} <-
           ApiClient.list_models(%{provider: @models_provider}, api_key),
         %{data: %{data: page}} <- body do
      {:ok, page}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, "Unexpected Kaapi list_models response: #{safe_inspect(other)}"}
    end
  end

  @spec insert_kaapi_provider(non_neg_integer(), String.t()) ::
          {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  defp insert_kaapi_provider(organization_id, api_key) do
    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "kaapi",
      keys: %{},
      secrets: %{"api_key" => api_key},
      is_active: true
    })
  end
end
