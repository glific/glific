defmodule Glific.ThirdParty.Kaapi do
  @moduledoc """
  Kaapi is our own internal services that handles all AI related features.
  """
  require Logger

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

      FunWithFlags.enable(
        :is_kaapi_enabled,
        for_actor: %{organization_id: params.organization_id}
      )

      {:ok, "KAAPI onboarding successful for org #{params.organization_id}"}
    else
      {:error, error} ->
        Glific.log_exception(%Error{
          message:
            "Kaapi onboarding failed for org_id=#{params.organization_id}, reason=#{inspect(error)}"
        })

        {:error, "KAAPI onboarding failed for org #{params.organization_id}: #{inspect(error)}"}
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
            "Assistant import failed in kaapi: organization_id=#{organization_id}, assistant_id=#{assistant_id}, reason=#{inspect(reason)}"
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
    config_blob = build_config_blob(params, params.knowledge_base_ids)

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
            reason: inspect(reason)
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
    config_blob = build_config_blob(params, params.knowledge_base_ids)

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
            reason: inspect(reason)
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
            reason: inspect(reason)
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
        Appsignal.send_error(
          %Error{
            message: "Kaapi AI Assistant delete failed for assistant_id=#{assistant_id}",
            organization_id: organization_id,
            reason: inspect(reason)
          },
          []
        )

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
        Appsignal.send_error(
          %Error{
            message: "Failed to create Kaapi Knowledge Base creation job",
            organization_id: organization_id,
            reason: inspect(reason)
          },
          []
        )

        {:error, reason}
    end
  end

  @spec build_config_blob(map(), list(String.t())) :: map()
  defp build_config_blob(params, knowledge_base_ids) do
    completion_params = %{
      model: params.model || "gpt-4o",
      instructions: params.prompt || "You are a helpful assistant",
      temperature: params.temperature || 1.0,
      knowledge_base_ids: knowledge_base_ids
    }

    %{
      completion: %{
        type: "text",
        provider: params[:provider] || "openai",
        params: completion_params
      }
    }
  end

  # Error type strings surfaced in webhook logs and flow failure path.
  # Each string is checked as a substring of the Kaapi error message body.
  @kaapi_error_types ~w(transcription_failed unsupported_format duration_exceeded rate_limited timeout service_unavailable)

  @doc """
  Initiates async Speech-to-Text via Kaapi unified LLM API.

  Downloads audio from `audio_url`, encodes it as base64, and calls Kaapi.
  Kaapi will POST the result to `callback_url` with `request_metadata` echoed back
  so the flow can be resumed. Returns `%{success: true}` on successful initiation.

  Optional `opts` map keys: `provider`, `model`, `language` — override defaults when provided.
  """
  @spec speech_to_text(String.t(), String.t(), map(), non_neg_integer(), map()) :: map()
  def speech_to_text(audio_url, callback_url, request_metadata, organization_id, opts \\ %{}) do
    with {:ok, encoded_audio} <- GupshupClient.download_media_content(audio_url, organization_id),
         {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         payload = stt_payload(encoded_audio, callback_url, request_metadata, opts),
         {:ok, body} <- ApiClient.call_llm(payload, secrets["api_key"]) do
      Map.merge(%{success: true}, body)
    else
      {:error, :download_failed} ->
        %{success: false, error_type: "unsupported_format", reason: "Audio file download failed"}

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
      Map.merge(%{success: true}, body)
    else
      error ->
        handle_kaapi_error(error, organization_id, "TTS", "service_unavailable")
    end
  end

  @spec handle_kaapi_error(tuple(), non_neg_integer(), String.t(), String.t()) :: map()
  defp handle_kaapi_error({:error, %{status: 429}}, _org_id, _label, _fallback),
    do: %{success: false, error_type: "rate_limited", reason: "Rate limit exceeded"}

  defp handle_kaapi_error({:error, %{status: 408}}, _org_id, _label, _fallback),
    do: %{success: false, error_type: "timeout", reason: "Request timed out"}

  defp handle_kaapi_error({:error, :timeout}, _org_id, _label, _fallback),
    do: %{success: false, error_type: "timeout", reason: "Request timed out"}

  defp handle_kaapi_error({:error, %{status: status, body: body}}, _org_id, _label, _fallback)
       when status in 500..599,
       do: %{success: false, error_type: "service_unavailable", reason: classify_error(body)}

  defp handle_kaapi_error({:error, %{status: _status, body: body}}, _org_id, _label, _fallback),
    do: %{success: false, error_type: "transcription_failed", reason: classify_error(body)}

  defp handle_kaapi_error({:error, reason}, organization_id, label, fallback_type) do
    Glific.log_exception(%Error{
      message: "Kaapi #{label} failed for org_id=#{organization_id}, reason=#{inspect(reason)}"
    })

    %{success: false, error_type: fallback_type, reason: inspect(reason)}
  end

  @spec classify_error(map() | String.t() | any()) :: String.t()
  defp classify_error(body) when is_map(body) do
    error_message = body["error"] || body["message"] || inspect(body)

    error_message =
      if is_binary(error_message),
        do: String.downcase(error_message),
        else: inspect(error_message)

    Enum.find(@kaapi_error_types, "transcription_failed", &String.contains?(error_message, &1))
  end

  defp classify_error(body), do: inspect(body)

  @spec stt_payload(String.t(), String.t(), map(), map()) :: map()
  defp stt_payload(encoded_audio, callback_url, request_metadata, opts) do
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
            params: %{
              model: opts[:model] || "gemini-2.5-pro",
              instructions: "Transcribe the audio verbatim",
              input_language: opts[:language] || "auto",
              temperature: 0.5,
              output_language: "english"
            }
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
              model: opts[:model] || "gemini-2.5-pro-preview-tts",
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
            reason: inspect(reason),
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
            message:
              "KAAPI config delete failed for org_id=#{organization_id}, config=#{uuid}, reason=#{inspect(reason)}"
          },
          []
        )

        {:error, reason}
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
