defmodule Glific.Providers.Gupshup.ApiClient do
  @moduledoc """
  Https API client to interact with Gupshup
  """
  alias Glific.Partners
  alias Plug.Conn.Query
  import GlificWeb.Gettext

  @gupshup_msg_url "https://api.gupshup.io/wa/api/v1"
  @gupshup_api_url "https://api.gupshup.io/sm/api/v1"

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
           false <- is_nil(bsp_credentials.secrets["api_key"]) do
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
  Fetching HSM templates for an organization
  """
  @spec get_templates(non_neg_integer()) :: Tesla.Env.result() | {:error, String.t()}
  def get_templates(org_id) do
    with {:ok, credentials} <- get_credentials(org_id) do
      template_url = @gupshup_api_url <> "/template/list/" <> credentials.app_name
      gupshup_get(template_url, credentials.api_key)
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

  @doc """
  Update a contact phone as opted in
  """
  @spec optin_contact(non_neg_integer(), map()) :: Tesla.Env.result() | {:error, String.t()}
  def optin_contact(org_id, payload) do
    get_credentials(org_id)

    with {:ok, credentials} <- get_credentials(org_id) do
      url = @gupshup_api_url <> "/app/opt/in/" <> credentials.app_name
      gupshup_post(url, payload, credentials.api_key)
    end
  end

  @doc """
  Fetch opted in contacts data from providers server
  """
  @spec fetch_opted_in_contacts(non_neg_integer(), non_neg_integer()) ::
          Tesla.Env.result() | {:error, String.t()}
  def fetch_opted_in_contacts(org_id, page) do
    with {:ok, credentials} <- get_credentials(org_id),
         do: users_get(credentials.api_key, credentials.app_name, page)
  end

  @doc """
  Build the Gupshup user list url
  """
  @spec users_get(String.t(), String.t(), non_neg_integer()) ::
          Tesla.Env.result() | {:error, String.t()}
  def users_get(api_key, app_name, page \\ 0) do
    url = @gupshup_api_url <> "/users/" <> app_name <> "?maxResult=5000&pageNo=#{page}"
    gupshup_get(url, api_key)
  end
end
