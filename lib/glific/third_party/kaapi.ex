defmodule Glific.ThirdParty.Kaapi do
  @moduledoc """
  Kaapi is our own internal services that handles all AI related features.
  """
  require Logger

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

  @doc """
  Onboard an organization to Kaapi
  """
  @spec onboard(map()) :: :ok
  def onboard(params) do
    with {:ok, %{data: %{api_key: api_key}}} <- ApiClient.onboard_to_kaapi(params),
         {:ok, _} <- insert_kaapi_provider(params.organization_id, api_key) do
      Logger.info("KAAPI onboarding success for org: #{params.organization_id}")
      {:ok, "KAAPI onboarding successful for org #{params.organization_id}"}
    else
      {:error, error} ->
        Logger.error(
          "KAAPI onboarding failed for org: #{params.organization_id}, reason: #{inspect(error)}"
        )

        {:error, "KAAPI onboarding failed for org #{params.organization_id}: #{inspect(error)}"}
    end
  end

  @doc """
  Ingest an AI assistant to Kaapi
  """
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
        Logger.error(
          "KAAPI_INGEST failed for org: #{organization_id}, assistant: #{assistant_id}, reason: #{inspect(reason)}"
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
