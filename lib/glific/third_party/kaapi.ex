defmodule Glific.ThirdParty.Kaapi do
  @moduledoc """
  Kaapi is our own internal services that handles all AI related features.
  """
  require Logger

  alias Glific.Partners
  alias Glific.Partners.Credential
  alias Glific.ThirdParty.Kaapi.ApiClient

  # Update all Error struct data in this format
  defmodule Error do
    @moduledoc """
    Custom error module for Kaapi API failures.
    Since Kaapi is a backend service (NGOs don’t interact with it directly),
    sending errors to them won’t resolve the issue.
    Reporting these failures to AppSignal lets us detect and fix problems
    """
    defexception [:message, :reason, :status, :organization_id]
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
    config_blob = build_config_blob(params, params.vector_store_ids)

    body = %{
      name: params.name,
      description: params[:description] || "",
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
            message:
              "Kaapi Config creation failed for org_id=#{organization_id}, name=#{params.name}, reason=#{inspect(reason)}"
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
            message:
              "Kaapi AI Assistant update failed for org_id=#{params.organization_id}, assistant_id=#{assistant_id}), reason=#{inspect(reason)}"
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
            message:
              "Kaapi AI Assistant delete failed for org_id=#{organization_id}, assistant_id=#{assistant_id}), reason=#{inspect(reason)}"
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
  defp build_config_blob(params, vector_store_ids) do
    completion_params = %{
      model: params.model || "gpt-4o-mini",
      instructions: params.prompt || "You are a helpful assistant",
      temperature: params.temperature || 1.0,
      tools: [
        %{
          type: "file_search",
          vector_store_ids: vector_store_ids
        }
      ]
    }

    %{
      completion: %{
        provider: params[:provider] || "openai",
        params: completion_params
      }
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
