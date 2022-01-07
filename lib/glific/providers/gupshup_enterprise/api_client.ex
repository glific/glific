defmodule Glific.Providers.Gupshup.Enterprise.ApiClient do
  @moduledoc """
  Http API client to interact with Gupshup
  """
  alias Glific.Partners
  alias Plug.Conn.Query
  import GlificWeb.Gettext

  @gupshup_enterprise_url "https://media.smsgupshup.com/GatewayAPI/rest"
  @default_send_message_params %{
    "method" => "SendMessage",
    "format" => "json",
    "v" => "1.1",
    "auth_scheme" => "plain",
    "msg_type" => "DATA_TEXT"
  }
  @default_optin_params %{
    "method" => "OPT_IN",
    "format" => "json",
    "v" => "1.1",
    "auth_scheme" => "plain",
    "channel" => "WHATSAPP"
  }
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
  def gupshup_post(url, payload, credentials), do: post(url, Map.merge(payload, credentials))

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
        {:ok, %{"userid" => user_id, "password" => password}}
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
    with {:ok, credentials} <- get_credentials(org_id) do
      %{"text" => msg_body} = payload["message"] |> Jason.decode!()

      msg_payload =
        @default_send_message_params
        |> Map.put("send_to", payload["destination"])
        |> Map.put("msg", msg_body)

      gupshup_post(@gupshup_enterprise_url, msg_payload, credentials)
    end
  end

  @doc """
  Update a contact phone as opted in
  """
  @spec optin_contact(non_neg_integer(), map()) :: Tesla.Env.result() | {:error, String.t()}
  def optin_contact(org_id, payload) do
    with {:ok, credentials} <- get_credentials(org_id) do
      gupshup_post(
        @gupshup_enterprise_url,
        Map.merge(@default_optin_params, payload),
        credentials
      )
    end
  end
end
