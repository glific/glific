defmodule Glific.Providers.Gupshup.ApiClient do
  @moduledoc """
  Http API client to intract with Gupshup
  """
  alias Glific.Partners
  alias Plug.Conn.Query

  @gupshup_url "https://api.gupshup.io/sm/api/v1"

  use Tesla
  # you can add , log_level: :debug to the below if you want debugging info
  plug Tesla.Middleware.Logger

  plug Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1

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
      {:error, "No active BSP available"}
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
      template_url = @gupshup_url <> "/template/list/" <> credentials.app_name
      gupshup_get(template_url, credentials.api_key)
    end
  end

  @doc """
  Submitting HSM template for approval
  """
  @spec submit_template_for_approval(non_neg_integer(), map()) ::
          Tesla.Env.result() | {:error, any()}
  def submit_template_for_approval(org_id, payload) do
    get_credentials(org_id)

    with {:ok, credentials} <- get_credentials(org_id) do
      template_url = @gupshup_url <> "/template/add/" <> credentials.app_name
      gupshup_post(template_url, payload, credentials.api_key)
    end
  end

  @doc """
  Sending HSM template to contact
  """
  @spec send_template(non_neg_integer(), map()) :: Tesla.Env.result() | {:error, String.t()}
  def send_template(org_id, payload) do
    get_credentials(org_id)

    with {:ok, credentials} <- get_credentials(org_id) do
      template_url = @gupshup_url <> "/template/msg"
      gupshup_post(template_url, payload, credentials.api_key)
    end
  end

  @doc """
  Sending HSM template to contact
  """
  @spec send_message(non_neg_integer(), map()) :: Tesla.Env.result() | any()
  def send_message(org_id, payload) do
    get_credentials(org_id)

    with {:ok, credentials} <- get_credentials(org_id) do
      url = @gupshup_url <> "/msg"
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
      url = @gupshup_url <> "/app/opt/in/" <> credentials.app_name
      gupshup_post(url, payload, credentials.api_key)
    end
  end

  @doc """
  Fetch opted in contacts data from providers server
  """
  @spec fetch_opted_in_contacts(non_neg_integer()) :: Tesla.Env.result() | {:error, String.t()}
  def fetch_opted_in_contacts(org_id) do
    get_credentials(org_id)

    with {:ok, credentials} <- get_credentials(org_id) do
      template_url = @gupshup_url <> "/users/" <> credentials.app_name
      gupshup_get(template_url, credentials.api_key)
    end
  end

  @doc """
  Update BSP credentials
  """
  @spec update_credentials(non_neg_integer(), String.t(), String.t()) :: {:ok, any} | {:error, any}
  def update_credentials(org_id, api_key, app_name) do
    cred = %{
      is_active: true,
      keys: %{
        "api_end_point" => "https://api.gupshup.io/sm/api/v1",
        "bsp_limit" => 40,
        "handler" => "Glific.Providers.Gupshup.Message",
        "url" => "https://gupshup.io/",
        "worker" => "Glific.Providers.Gupshup.Worker"
      },
      organization_id: org_id,
      secrets: %{
        "api_key" => api_key,
        "app_name" => app_name
      },
      shortcode: "gupshup"
    }
    {:ok, gupshup} = Partners.get_credential(%{organization_id: org_id, shortcode: "gupshup"})
    Partners.update_credential(gupshup, cred)
  end
end
