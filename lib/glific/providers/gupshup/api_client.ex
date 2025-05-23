defmodule Glific.Providers.Gupshup.ApiClient do
  @moduledoc """
  Https API client to interact with Gupshup
  """
  alias Glific.Partners
  alias Plug.Conn.Query
  use Gettext, backend: GlificWeb.Gettext

  @gupshup_msg_url "https://api.gupshup.io/wa/api/v1"

  use Tesla
  # you can add , log_level: :debug to the below if you want debugging info
  plug(Tesla.Middleware.Logger)

  plug(Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1
  )

  @doc """
  Making Tesla get call and adding api key in header
  """
  @spec gupshup_get(String.t(), String.t()) :: Tesla.Env.result()
  def gupshup_get(url, api_key), do: get(url, headers: [{"apikey", api_key}])

  @doc """
  Making Tesla post call and adding api key in header
  """
  @spec gupshup_post(String.t(), any(), String.t()) :: Tesla.Env.result()
  def gupshup_post(url, payload, api_key), do: post(url, payload, headers: [{"apikey", api_key}])

  @spec get_credentials(non_neg_integer()) :: {:error, String.t()} | {:ok, map()}
  defp get_credentials(org_id) do
    organization = Partners.organization(org_id)

    if is_nil(organization.services["bsp"]) do
      {:error, dgettext("errors", "No active BSP available")}
    else
      bsp_credentials = organization.services["bsp"]

      with false <- is_nil(bsp_credentials.secrets["api_key"]),
           false <- is_nil(bsp_credentials.secrets["app_name"]) do
        api_key = bsp_credentials.secrets["api_key"]
        app_name = bsp_credentials.secrets["app_name"]
        {:ok, %{api_key: api_key, app_name: app_name}}
      else
        _ ->
          {:error,
           "Please check your credential settings and ensure you have added the API Key and App Name also"}
      end
    end
  end

  @doc """
  Sending message to contact
  """
  @spec send_message(non_neg_integer(), map()) :: Tesla.Env.result() | any()
  def send_message(org_id, payload) do
    with {:ok, credentials} <- get_credentials(org_id) do
      url = @gupshup_msg_url <> "/msg"
      gupshup_post(url, payload, credentials.api_key)
    end
  end
end
