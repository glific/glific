defmodule Glific.ThirdParty.Kaapi do
  @moduledoc """
  Kaapi is our own internal services that handles all AI related features.
  """
  require Logger

  alias Glific.Partners
  alias Glific.ThirdParty.Kaapi.ApiClient

  defmodule Error do
    @moduledoc """
    Custom error module for Kaapi webhook failures.
    Since Kaapi is a backend service (NGOs don’t interact with it directly),
    sending errors to them won’t resolve the issue.
    Reporting these failures to AppSignal lets us detect and fix problems
    """
    defexception [:message]
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

  @spec onboard(map()) :: :ok
  def onboard(params) do
    with {:ok, %{api_key: api_key}} <- ApiClient.onboard_to_kaapi(params),
         {:ok, _} <- insert_kaapi_provider(params.organization_id, api_key) do
      Logger.info("KAAPI onboarding success for org: #{params.organization_id}")
      {:ok, "KAAPI onboarding successful"}
    else
      {:error, error} ->
        Logger.error(
          "KAAPI onboarding failed for org: #{params.organization_id}, reason: #{inspect(error)}"
        )

        {:error, error}
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
