defmodule Glific.ThirdParty.Kaapi do
  @moduledoc """
  Kaapi is our own internal services that handles all AI related features.
  """
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

  def onboard(params) do
    ApiClient.onboard_to_kaapi(params)
  end
end
