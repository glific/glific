defmodule Glific.Providers.Gupshup.PartnerAPI do
  @moduledoc """
  A module to handle fetching tier related information like quality rating and app rating using partner API
  """

  alias Glific.{
    Caches,
    Partners,
    Partners.Saas
  }

  use Tesla
  alias Plug.Conn.Query

  plug(Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1
  )

  @partner_url "https://partner.gupshup.io/partner/account"
  @app_url "https://partner.gupshup.io/partner/app/"
  @global_organization_id 0

  @doc """
    Fetch App details based on API key and App name
  """
  @spec fetch_app_details(non_neg_integer()) :: any()
  def fetch_app_details(org_id) do
    organization = Partners.organization(org_id)
    gupshup_secrets = organization.services["bsp"].secrets

    post_request(
      @partner_url <> "/api/appLink",
      %{
        apiKey: gupshup_secrets["api_key"],
        appName: gupshup_secrets["app_name"]
      },
      token_type: :partner_token
    )
    |> case do
      {:ok, res} ->
        res["partnerApps"]

      error ->
        error
    end
  end

  @doc """
  Fetches Partner token and App Access token to get tier information
  for an organization with input app id
  """
  @spec get_quality_rating(non_neg_integer(), String.t()) :: {:error, any} | {:ok, map()}
  def get_quality_rating(organization_id, _phone) do
    (@app_url <> app_id!(organization_id) <> "/ratings")
    |> get_request(token_type: :app_token, org_id: organization_id)
    |> case do
      {:ok, res} ->
        {:ok,
         %{
           current_limit: res["currentLimit"],
           event: res["event"],
           event_time: res["eventTime"],
           previous_limit: res["oldLimit"]
         }}

      error ->
        {:error, "Error while getting the ratings. #{inspect(error)}"}
    end
  end

  # Get Partner token
  @spec get_partner_token :: {:ok, map()} | {:error, any}
  defp get_partner_token do
    # disabling the cache refresh because by default whenever
    # we fetch the info from cache it refreshes the TTL
    {:ok, partner_token} =
      Caches.get(@global_organization_id, "partner_token", refresh_cache: false)

    if partner_token,
      do: {:ok, %{partner_token: partner_token}},
      else: fetch_partner_token()
  end

  @spec fetch_partner_token :: {:ok, map()} | {:error, any}
  defp fetch_partner_token do
    url = @partner_url <> "/login"
    credentials = Saas.isv_credentials()
    request_params = %{"email" => credentials["email"], "password" => credentials["password"]}

    post(url, request_params, headers: [])
    |> case do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        res = Jason.decode!(body)

        {:ok, token} =
          Caches.set(@global_organization_id, "partner_token", res["token"], ttl: :timer.hours(22))

        {:ok, %{partner_token: token}}

      {_status, response} ->
        {:error, "Could not fetch the partner token #{inspect(response)}"}
    end
  end

  @spec get_partner_app_token(non_neg_integer) ::
          {:error, String.t()} | {:ok, %{partner_app_token: any}}
  defp get_partner_app_token(org_id) do
    {:ok, partner_app_token} = Caches.get(org_id, "partner_app_token", refresh_cache: false)

    if partner_app_token,
      do: {:ok, %{partner_app_token: partner_app_token}},
      else: fetch_partner_app_token(org_id)
  end

  @spec fetch_partner_app_token(non_neg_integer) ::
          {:error, String.t()} | {:ok, %{partner_app_token: any}}
  defp fetch_partner_app_token(org_id) do
    url = @app_url <> app_id!(org_id) <> "/token"

    get_request(url, token_type: :partner_token)
    |> case do
      {:ok, res} ->
        app_token = get_in(res, ["token", "token"])
        Caches.set(org_id, "partner_app_token", app_token, ttl: :timer.hours(22))
        {:ok, %{partner_app_token: app_token}}

      {:error, error} ->
        {:error, "Could not fetch the partner app token #{inspect(error)}"}
    end
  end

  @spec headers(atom(), Keyword.t()) :: list()
  defp headers(:app_token, opts) do
    org_id = Keyword.get(opts, :org_id)
    {:ok, %{partner_app_token: partner_app_token}} = get_partner_app_token(org_id)

    [{"token", partner_app_token}, {"Authorization", partner_app_token}]
  end

  defp headers(:partner_token, _opts) do
    {:ok, %{partner_token: partner_token}} = get_partner_token()
    [{"token", partner_token}, {"Authorization", partner_token}]
  end

  defp post_request(url, data, opts) do
    req_headers = headers(Keyword.get(opts, :token_type), opts)

    post(url, data, headers: req_headers)
    |> case do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, Jason.decode!(body)}

      err ->
        {:error, "#{inspect(err)}"}
    end
  end

  defp get_request(url, opts) do
    req_headers = headers(Keyword.get(opts, :token_type), opts)

    get(url, headers: req_headers)
    |> case do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, Jason.decode!(body)}

      err ->
        {:error, "#{inspect(err)}"}
    end
  end

  @spec app_id(non_neg_integer()) :: {:ok, String.t()} | {:error, String.t()}
  defp app_id(org_id) do
    organization = Partners.organization(org_id)
    gupshup_secrets = organization.services["bsp"].secrets

    if gupshup_secrets["app_id"] in [nil, ""] do
      {:error, "App Id not found."}
    else
      {:ok, gupshup_secrets["app_id"]}
    end
  end

  @spec app_id!(non_neg_integer()) :: String.t()
  defp app_id!(org_id) do
    {:ok, app_id} = app_id(org_id)
    app_id
  end
end
