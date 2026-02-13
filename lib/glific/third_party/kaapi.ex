defmodule Glific.ThirdParty.Kaapi do
  @moduledoc """
  Kaapi is our own internal services that handles all AI related features.
  """
  require Logger

  # Replace this with the new exception after PR #4365 is merged
  alias Glific.Flows.Webhook.Error
  alias Glific.Partners
  alias Glific.Partners.Credential
  alias Glific.ThirdParty.Kaapi.ApiClient

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
  Create an AI assistant in Kaapi, send error to Appsignal if failed.
  """
  @spec create_assistant(map(), non_neg_integer()) :: {:ok, map()} | {:error, map() | binary()}
  def create_assistant(openai_response, organization_id) do
    params = %{
      name: openai_response.name,
      model: openai_response.model,
      assistant_id: openai_response.id,
      organization_id: organization_id,
      instructions: openai_response.instructions,
      temperature: openai_response.temperature
    }

    with {:ok, secrets} <- fetch_kaapi_creds(organization_id),
         {:ok, result} <-
           ApiClient.create_assistant(params, secrets["api_key"]) do
      Logger.info(
        "KAAPI AI Assistant creation successful for org: #{organization_id}, assistant: #{params.assistant_id}"
      )

      {:ok, result}
    else
      {:error, reason} ->
        Appsignal.send_error(
          %Error{
            message:
              "Kaapi AI Assistant creation failed for org_id=#{params.organization_id}, assistant_id=#{params.assistant_id}, reason=#{inspect(reason)}"
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
      Logger.info(
        "KAAPI AI Assistant delete successful for org: #{organization_id}, assistant: #{assistant_id}"
      )

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
              "Kaapi config delete failed for org_id=#{organization_id}, config=#{uuid}, reason=#{inspect(reason)}"
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
