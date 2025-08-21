defmodule Glific.ThirdParty.Kaapi do
  @moduledoc """
  Kaapi is our own internal services that handles all AI related features.
  """
  require Logger

  # Replace this with the new exception after PR #4365 is merged
  alias Glific.Flows.Webhook.Error
  alias Glific.Partners
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

  @spec onboard(map()) :: :ok
  def onboard(params) do
    with {:ok, %{api_key: api_key}} <- ApiClient.onboard_to_kaapi(params),
         {:ok, _} <- insert_kaapi_provider(params.organization_id, api_key) do
      Logger.info("KAAPI onboarding success for org: #{params.organization_id}")
    else
      {:error, error} ->
        Logger.error(
          "KAAPI onboarding failed for org: #{params.organization_id}, reason: #{inspect(error)}"
        )
    end
  end

  @spec create_assistant(map(), non_neg_integer()) :: {:ok, map()} | {:error, map() | binary()}
  def create_assistant(openai_response, organization_id) do
    params = %{
      name: openai_response.name,
      model: openai_response.model,
      assistant_id: openai_response.id,
      instructions: "you are a helpful asssitant",
      organization_id: organization_id
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
              "Kaapi AI Assistant creation failed for org_id=#{params.organization_id}, assistant_id=#{params.assistant_id})",
            reason: reason
          },
          []
        )

        {:error, reason}
    end
  end

  @spec update_assistant(map(), non_neg_integer()) :: {:ok, map()} | {:error, map() | binary()}
  def update_assistant(params, organization_id) do
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
           ApiClient.update_assistant(params.assistant_id, params, secrets["api_key"]) do
      Logger.info(
        "KAAPI AI Assistant update successful for org: #{organization_id}, assistant: #{params.assistant_id}"
      )

      {:ok, result}
    else
      {:error, reason} ->
        Appsignal.send_error(
          %Error{
            message:
              "Kaapi AI Assistant update failed for org_id=#{params.organization_id}, assistant_id=#{params.assistant_id})",
            reason: reason
          },
          []
        )

        {:error, reason}
    end
  end

  @spec insert_kaapi_provider(non_neg_integer(), String.t()) ::
          {:ok, :created | :already_active} | {:error, any()}
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
