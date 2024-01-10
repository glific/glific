defmodule Glific.Providers.Maytapi.ApiClient do
  @moduledoc """
  Https API client to interact with Maytapi
  """

  alias Glific.Partners

  @maytapi_url "https://api.maytapi.com/api"

  use Tesla

  @doc """
  Making Tesla get call and adding api key in header
  """
  @spec maytapi_get(String.t(), String.t()) :: Tesla.Env.result()
  def maytapi_get(url, token),
    do:
      get(url,
        headers:
          headers = [
            {"accept", "application/json"},
            {"x-maytapi-key", token}
          ]
      )

  @doc false
  @spec fetch_credentials(non_neg_integer) :: nil | {:ok, any} | {:error, any}
  def fetch_credentials(organization_id) do
    organization = Partners.organization(organization_id)

    organization.services["maytapi"]
    |> case do
      nil ->
        {:error, "Maytapi is not active"}

      credentials ->
        credentials.secrets
    end
  end

  @doc """
  Fetches group using Mytapi API and sync it in Glific

  ## Examples

      iex> get_whatsapp_group_details()
      [%Group{}, ...]

  """
  @spec get_whatsapp_group_details(non_neg_integer()) :: list() | {:error, any()}
  def get_whatsapp_group_details(org_id) do
    secrets = Maytapi.fetch_credentials(org_id)
    phone_id = secrets["phone_id"]
    product_id = secrets["product_id"]
    token = secrets["token"]

    url = @maytapi_url <> "/#{product_id}/#{phone_id}/getGroups"

    maytapi_get(url, token)
  end
end
