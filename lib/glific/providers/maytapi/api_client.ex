defmodule Glific.Providers.Maytapi.ApiClient do
  @moduledoc """
  Https API client to interact with Maytapi
  """

  alias Glific.Partners

  @maytapi_url "https://api.maytapi.com/api"

  use Tesla

  @spec headers(String.t()) :: list()
  defp headers(token),
    do: [
      {"accept", "application/json"},
      {"x-maytapi-key", token}
    ]

  @doc """
  Making Tesla get call and adding api key in header
  """
  @spec maytapi_get(String.t(), String.t()) :: Tesla.Env.result()
  def maytapi_get(url, token),
    do: get(url, headers: headers(token))

  @doc """
  Making Tesla post call and adding api key in header
  """
  @spec maytapi_post(String.t(), any(), String.t()) :: Tesla.Env.result()
  def maytapi_post(url, payload, token),
    do: post(url, payload, headers: headers(token))

  @doc false
  @spec fetch_credentials(non_neg_integer) :: nil | {:ok, any} | {:error, any}
  def fetch_credentials(organization_id) do
    organization = Partners.organization(organization_id)

    organization.services["maytapi"]
    |> case do
      nil ->
        {:error, "Maytapi is not active"}

      credentials ->
        {:ok, credentials.secrets}
    end
  end

  @doc """
  Fetches group using Maytapi API and sync it in Glific

  ## Examples

      iex> list_wa_groups()
      [%Group{}, ...]

  """
  @spec list_wa_groups(non_neg_integer()) :: Tesla.Env.result()
  def list_wa_groups(org_id) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      phone_id = secrets["phone_id"]
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/#{phone_id}/getGroups"

      maytapi_get(url, token)
    end
  end

  @doc """
  Sending message to contact
  """
  @spec send_message(non_neg_integer(), map()) :: Tesla.Env.result()
  def send_message(org_id, payload) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      phone_id = secrets["phone_id"]
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/#{phone_id}/sendMessage"

      maytapi_post(url, payload, token)
    end
  end
end
