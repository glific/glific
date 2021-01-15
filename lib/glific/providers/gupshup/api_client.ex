defmodule Glific.Providers.Gupshup.ApiClient do
  @moduledoc """
  Http API client to intract with Gupshup
  """
  alias Plug.Conn.Query
  alias Glific.Partners

  @gupshup_url "https://api.gupshup.io/sm/api/v1"

  use Tesla
  # you can add , log_level: :debug to the below if you want debugging info
  plug Tesla.Middleware.Logger

  plug Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1

  @spec get(String.t(), String.t()) :: Tesla.Env.result()
  defp get(url, api_key), do: Tesla.get(url, headers: [{"apikey", api_key}])

  @spec post(String.t(), any(), String.t()) :: Tesla.Env.result()
  defp post(url, payload, api_key), do: Tesla.post(url, payload, headers: [{"apikey", api_key}])

  @spec get_credentials(non_neg_integer()) :: {:error, String.t() | {:ok, map()}}
  defp get_credentials(org_id) do
    organization = Partners.organization(org_id)

    if is_nil(organization.services["bsp"]) do
      {:error, "No active BSP available"}
    else
      bsp_credentials = organization.services["bsp"]
      api_key = bsp_credentials.secrets["api_key"]
      app_name = bsp_credentials.secrets["app_name"]

      {:ok, %{api_key: api_key, app_name: app_name}}
    end
  end

  @doc """
  Fetching HSM templates for an organization
  """
  @spec get_templates(non_neg_integer()) :: Tesla.Env.result() | {:error, String.t()}
  def get_templates(org_id) do
    get_credentials(org_id)
    |> case do
      {:ok, credentials} ->
        template_url = @gupshup_url <> "/template/list/" <> credentials.app_name
        get(template_url, credentials.api_key)

      _ ->
        {:error, "error"}
    end
  end

  @doc """
  Submitting HSM template for approval
  """
  @spec submit_template_for_approval(non_neg_integer(), map()) ::
          Tesla.Env.result() | {:error, String.t()}
  def submit_template_for_approval(org_id, payload) do
    get_credentials(org_id)
    |> case do
      {:ok, credentials} ->
        template_url = @gupshup_url <> "/template/add/" <> credentials.app_name
        post(template_url, payload, credentials.api_key)

      _ ->
        {:error, "error"}
    end
  end

  @doc """
  Sending HSM template to contact
  """
  @spec send_template(non_neg_integer(), map()) :: Tesla.Env.result() | {:error, String.t()}
  def send_template(org_id, payload) do
    get_credentials(org_id)
    |> case do
      {:ok, credentials} ->
        template_url = @gupshup_url <> "/template/msg"
        post(template_url, payload, credentials.api_key)

      _ ->
        {:error, "error"}
    end
  end

  @doc """
  Sending HSM template to contact
  """
  @spec send_message(non_neg_integer(), map()) :: Tesla.Env.result() | {:error, String.t()}
  def send_message(org_id, payload) do
    get_credentials(org_id)
    |> case do
      {:ok, credentials} ->
        url = @gupshup_url <> "/msg"
        post(url, payload, credentials.api_key)

      _ ->
        {:error, "error"}
    end
  end

  @doc """
    Update a contact phone as opted in
  """
  @spec optin_contact(non_neg_integer(), map()) :: Tesla.Env.result() | {:error, String.t()}
  def optin_contact(org_id, payload) do
    get_credentials(org_id)
    |> case do
      {:ok, credentials} ->
        url = @gupshup_url <> "/app/opt/in/" <> credentials.app_name
        post(url, payload, credentials.api_key)

      _ ->
        {:error, "error"}
    end
  end

  @doc """
  Fetch opted in contacts data from providers server
  """
  @spec optin_contact(non_neg_integer()) :: Tesla.Env.result() | {:error, String.t()}
  def fetch_opted_in_contacts(org_id) do
    get_credentials(org_id)
    |> case do
      {:ok, credentials} ->
        template_url = @gupshup_url <> "/users/" <> credentials.app_name
        get(template_url, credentials.api_key)

      _ ->
        {:error, "error"}
    end
  end
end
