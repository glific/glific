defmodule Glific.Providers.Gupshup.Enterprise.ApiClient do
  @moduledoc """
  Http API client to interact with Gupshup
  """
  alias Glific.Partners
  alias Plug.Conn.Query
  import GlificWeb.Gettext

  @gupshup_url "https://media.smsgupshup.com/GatewayAPI/rest"

  use Tesla
  # you can add , log_level: :debug to the below if you want debugging info
  plug(Tesla.Middleware.Logger)

  plug(Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1
  )

  @doc """
  Making Tesla post call and adding user_id and password from credentials
  """
  @spec gupshup_post(String.t(), any(), map()) :: Tesla.Env.result()
  def gupshup_post(url, payload, credentials) do
    payload =
      payload
      |> Map.put("user_id", credentials.user_id)
      |> Map.put("password", credentials.password)

    post(url, payload)
  end

  @spec get_credentials(non_neg_integer()) :: {:error, String.t()} | {:ok, map()}
  defp get_credentials(org_id) do
    organization = Partners.organization(org_id)

    if is_nil(organization.services["bsp"]) do
      {:error, dgettext("errors", "No active BSP available")}
    else
      bsp_credentials = organization.services["bsp"]

      with false <- is_nil(bsp_credentials.secrets["user_id"]),
           false <- is_nil(bsp_credentials.secrets["password"]) do
        user_id = bsp_credentials.secrets["user_id"]
        password = bsp_credentials.secrets["password"]
        {:ok, %{user_id: user_id, password: password}}
      else
        _ ->
          {:error,
           "Please check your credential settings and ensure you have added the user ID and password also"}
      end
    end
  end

  @doc """
  Sending message to contact
  """
  @spec send_message(non_neg_integer(), map()) :: Tesla.Env.result() | any()
  def send_message(org_id, payload) do
    get_credentials(org_id)

    with {:ok, credentials} <- get_credentials(org_id) do
      url = @gupshup_url
      gupshup_post(url, payload, credentials)
    end
  end

  @doc """
  Update a contact phone as opted in
  """
  @spec optin_contact(non_neg_integer(), map()) :: Tesla.Env.result() | {:error, String.t()}
  def optin_contact(org_id, payload) do
    get_credentials(org_id)

    with {:ok, credentials} <- get_credentials(org_id) do
      url = @gupshup_url
      gupshup_post(url, payload, credentials)
    end
  end
end
