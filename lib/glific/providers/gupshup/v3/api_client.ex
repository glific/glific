defmodule Glific.Providers.Gupshup.V3.ApiClient do
  @moduledoc """
  Client for the Gupshup partner V3 APIs, which take Meta's WhatsApp Cloud API payloads.
  """

  alias Glific.Caches
  alias Glific.Partners.Saas
  alias Glific.Providers.Gupshup.PartnerAPI
  alias Glific.SafeLog

  @partner_url "https://partner.gupshup.io/partner"
  @global_organization_id 0
  @token_ttl :timer.hours(22)

  @doc """
  Sends a message in Meta's Cloud API format, e.g. a template with a flow button.
  """
  @spec send_message(non_neg_integer(), map()) :: {:ok, Req.Response.t()} | {:error, any()}
  def send_message(org_id, body) do
    with {:ok, app_id} <- PartnerAPI.app_id(org_id),
         {:ok, headers} <- headers(org_id, app_id) do
      [
        url: "#{@partner_url}/app/#{app_id}/v3/message",
        json: body,
        headers: headers
      ]
      |> maybe_add_plug()
      |> Req.post()
      |> normalize_result()
    end
  end

  @spec headers(non_neg_integer(), String.t()) :: {:ok, list()} | {:error, String.t()}
  defp headers(org_id, app_id) do
    with {:ok, app_token} <- app_token(org_id, app_id) do
      {:ok, [authorization: app_token]}
    end
  end

  @spec app_token(non_neg_integer(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp app_token(org_id, app_id) do
    case Caches.get(org_id, "partner_app_token", refresh_cache: false) do
      {:ok, app_token} when is_binary(app_token) -> {:ok, app_token}
      _ -> fetch_app_token(org_id, app_id)
    end
  end

  @spec fetch_app_token(non_neg_integer(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp fetch_app_token(org_id, app_id) do
    with {:ok, partner_token} <- partner_token(),
         {:ok, %{status: 200, body: %{"token" => %{"token" => app_token}}}} <-
           request_app_token(app_id, partner_token) do
      Caches.set(org_id, "partner_app_token", app_token, ttl: @token_ttl)
      {:ok, app_token}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      error -> {:error, "Could not fetch the partner app token: #{SafeLog.safe_inspect(error)}"}
    end
  end

  @spec request_app_token(String.t(), String.t()) :: {:ok, Req.Response.t()} | {:error, any()}
  defp request_app_token(app_id, partner_token) do
    [url: "#{@partner_url}/app/#{app_id}/token", headers: [authorization: partner_token]]
    |> maybe_add_plug()
    |> Req.get()
  end

  @spec partner_token :: {:ok, String.t()} | {:error, String.t()}
  defp partner_token do
    case Caches.get(@global_organization_id, "partner_token", refresh_cache: false) do
      {:ok, partner_token} when is_binary(partner_token) -> {:ok, partner_token}
      _ -> fetch_partner_token()
    end
  end

  @spec fetch_partner_token :: {:ok, String.t()} | {:error, String.t()}
  defp fetch_partner_token do
    credentials = %{
      email: Saas.isv_credentials()["email"],
      password: Application.get_env(:glific, :gupshup_partner_client_secret)
    }

    [url: "#{@partner_url}/account/login", form: credentials]
    |> maybe_add_plug()
    |> Req.post()
    |> case do
      {:ok, %{status: 200, body: %{"token" => partner_token}}} ->
        Caches.set(@global_organization_id, "partner_token", partner_token, ttl: @token_ttl)
        {:ok, partner_token}

      error ->
        {:error, "Could not fetch the partner token: #{SafeLog.safe_inspect(error)}"}
    end
  end

  # ResponseHandler retries a send only on the bare timeout reasons Tesla returns.
  @spec normalize_result({:ok, Req.Response.t()} | {:error, any()}) ::
          {:ok, Req.Response.t()} | {:error, any()}
  defp normalize_result({:error, %Req.TransportError{reason: reason}}), do: {:error, reason}
  defp normalize_result(result), do: result

  @spec maybe_add_plug(Keyword.t()) :: Keyword.t()
  defp maybe_add_plug(opts) do
    if plug = Application.get_env(:glific, :gupshup_v3_req_plug) do
      Keyword.put(opts, :plug, plug)
    else
      opts
    end
  end
end
