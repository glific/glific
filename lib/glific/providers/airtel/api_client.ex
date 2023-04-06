defmodule Glific.Providers.Airtel.ApiClient do
  @moduledoc """
  Https API client to interact with Gupshup
  """
  alias Glific.Partners
  alias Plug.Conn.Query
  import GlificWeb.Gettext

  @airtel_url "https://iqwhatsapp.airtel.in/gateway/airtel-xchange/basic/whatsapp-manager"

  use Tesla
  # you can add , log_level: :debug to the below if you want debugging info
  plug(Tesla.Middleware.Logger)

  plug(Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1
  )

  @doc """
  Making Tesla post call and adding api key in header
  """
  @spec airtel_post(String.t(), any(), String.t()) :: Tesla.Env.result()
  def airtel_post(url, payload, authorization),
    do:
      post(url, Jason.encode!(payload),
        headers: [
          {"Authorization", authorization},
          {"Content-Type", "application/json"}
        ]
      )

  @doc """
  get auth credentials from header
  """
  @spec get_credentials(non_neg_integer()) :: {:error, String.t()} | {:ok, map()}
  def get_credentials(org_id) do
    organization = Partners.organization(org_id)

    if is_nil(organization.services["bsp"]) do
      {:error, dgettext("errors", "No active BSP available")}
    else
      bsp_credentials = organization.services["bsp"]

      user_name = bsp_credentials.secrets["user_id"]
      secret = bsp_credentials.secrets["password"]

      authorization = "Basic " <> Base.encode64("#{user_name}:#{secret}")

      {:ok, %{authorization: authorization}}
    end
  end

  @doc """
  Sending HSM template to contact
  """
  @spec send_template(non_neg_integer(), map()) :: Tesla.Env.result() | {:error, String.t()}
  def send_template(org_id, payload) do
    with {:ok, credentials} <- get_credentials(org_id) do
      template_url = @airtel_url <> "/v1/template/send"
      airtel_post(template_url, payload, credentials.authorization)
    end
  end

  @doc """
  Sending HSM template to contact
  """
  @spec get_url(atom()) :: String.t() | {:error, String.t()}
  def get_url(type) do
    case type do
      "text" -> @airtel_url <> "/v1/session/send/text"
      "quick_reply" -> @airtel_url <> "/v1/session/send/interactive/buttons"
      "list" -> @airtel_url <> "/v1/session/send/interactive/list"
      "image" -> @airtel_url <> "/v1/session/send/media"
      _ -> @airtel_url <> "/v1/session/send/media"
    end
  end

  @doc """
  Sending message to contact
  """
  @spec send_message(non_neg_integer(), map()) :: Tesla.Env.result() | any()
  def send_message(org_id, payload) do
    with {:ok, credentials} <- get_credentials(org_id) do
      url = get_url(payload["type"])

      airtel_post(url, payload, credentials.authorization)
    end
  end
end
