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

  # @doc """
  # Making Tesla get call and adding api key in header
  # """

  # @spec gupshup_get(String.t(), String.t()) :: Tesla.Env.result()
  # def gupshup_get(url, api_key), do: get(url, headers: [{"apikey", api_key}])

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

  # @doc """
  # Fetching HSM templates for an organization
  # """

  # @spec get_templates(non_neg_integer()) :: Tesla.Env.result() | {:error, String.t()}
  # def get_templates(org_id) do
  #   with {:ok, credentials} <- get_credentials(org_id) do
  #     template_url = @airtel_url <> "/template/list/" <> credentials.app_name
  #     gupshup_get(template_url, credentials.api_key)
  #   end
  # end

  # @doc """
  # Submitting HSM template for approval
  # """

  # @spec submit_template_for_approval(non_neg_integer(), map()) ::
  #         Tesla.Env.result() | {:error, any()}
  # def submit_template_for_approval(org_id, payload) do
  #   with {:ok, credentials} <- get_credentials(org_id) do
  #     template_url = @airtel_url <> "/template/add/" <> credentials.app_name
  #     opts = [headers: [{"apikey", credentials.api_key}], opts: [adapter: [recv_timeout: 10_000]]]
  #     # Adding a delay of 30 seconds when applying for template
  #     post(template_url, payload, opts)
  #   end
  # end

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

  # @doc """
  # Update a contact phone as opted in
  # """

  # @spec optin_contact(non_neg_integer(), map()) :: Tesla.Env.result() | {:error, String.t()}
  # def optin_contact(org_id, payload) do
  #   get_credentials(org_id)

  #   with {:ok, credentials} <- get_credentials(org_id) do
  #     url = @airtel_url <> "/app/opt/in/" <> credentials.app_name
  #     airtel_post(url, payload, credentials.api_key)
  #   end
  # end

  # @doc """
  # Fetch opted in contacts data from providers server
  # """

  # @spec fetch_opted_in_contacts(non_neg_integer()) :: Tesla.Env.result() | {:error, String.t()}
  # def fetch_opted_in_contacts(org_id) do
  #   with {:ok, credentials} <- get_credentials(org_id),
  #        do: users_get(credentials.api_key, credentials.app_name)
  # end

  # @doc """
  # Build the Gupshup user list url
  # """
  # @spec users_get(String.t(), String.t()) :: Tesla.Env.result() | {:error, String.t()}
  # def users_get(api_key, app_name) do
  #   url = @airtel_url <> "/users/" <> app_name
  #   gupshup_get(url, api_key)
  # end
end
