defmodule Glific.Providers.Gupshup.PartnerAPI do
  @moduledoc """
  A module to handle fetching tier related information like quality rating and app rating using partner API
  """

  alias Glific.{
    Caches,
    Partners,
    Partners.Saas
  }

  alias Plug.Conn.Query

  use Tesla
  plug(Tesla.Middleware.Logger)

  plug(Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1
  )

  @partner_url "https://partner.gupshup.io/partner/account"
  @app_url "https://partner.gupshup.io/partner/app/"
  @global_organization_id 0

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

  defp make_request(:post, url, data) do
    with {:ok, %{partner_token: partner_token}} <- get_partner_token() do
      default_headers = [{"token", partner_token}]

      post(url, data, headers: default_headers)
      |> case do
        {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
          {:ok, Jason.decode!(body)}

        err ->
          {:error, "#{inspect(err)}"}
      end
    end
  end

  @doc """
    Fetch App details based on API key and App name
  """
  @spec fetch_app_details(non_neg_integer()) :: any()
  def fetch_app_details(org_id) do
    organization = Partners.organization(org_id)
    gupshup_secrets = organization.services["bsp"].secrets

    make_request(:post, @partner_url <> "/api/appLink", %{
      apiKey: gupshup_secrets["api_key"],
      appName: gupshup_secrets["app_name"]
    })
    |> case do
      {:ok, res} ->
        res["partnerApps"]

      error ->
        error
    end
  end

  # fetches app id from phone using partner API
  @spec get_apps_details(non_neg_integer(), String.t()) :: {:ok, String.t()} | {:error, any}
  defp get_apps_details(organization_id, phone) do
    # Need to use Caches.fetch and do_get_apps_details should be used as fallback fn but somehow testcases are failing when used
    {:ok, app_id} = Caches.get(organization_id, {:app_id, phone})

    if app_id == false,
      do: do_get_apps_details(organization_id, phone),
      else: {:ok, app_id}
  end

  @spec do_get_apps_details(non_neg_integer(), String.t()) :: {:ok, String.t()} | {:error, any}
  defp do_get_apps_details(organization_id, phone) do
    url = @partner_url <> "/api/partnerApps"

    with {:ok, %{partner_token: partner_token}} <- get_partner_token(),
         {:ok, %Tesla.Env{status: 200, body: body}} = _response <-
           get(url, headers: [{"token", partner_token}]) do
      app_list =
        body
        |> Jason.decode!()
        |> Map.get("partnerAppsList")

      app = Enum.find(app_list, fn app -> app["phone"] == phone end)

      if app,
        do: Caches.set(organization_id, {:app_id, phone}, app["id"]),
        else: {:error, "App not found"}
    end
  end

  # fetches partner token first to get app access token
  @spec get_app_token(non_neg_integer(), String.t()) :: {:ok, map()} | {:error, any}
  defp get_app_token(organization_id, app_id) do
    with {:ok, %{partner_token: partner_token}} <- get_partner_token() do
      # Need to use Caches.fetch and do_get_apps_details should be used as fallback fn but somehow testcases are failing when used
      {:ok, app_token} = Caches.get(organization_id, {:app_token, app_id})

      if app_token == false,
        do: do_get_app_token(organization_id, partner_token, app_id),
        else: {:ok, %{app_token: app_token}}
    end
  end

  @spec do_get_app_token(non_neg_integer(), String.t(), String.t()) ::
          {:ok, map()} | {:error, any}
  defp do_get_app_token(organization_id, partner_token, app_id) do
    url = @app_url <> app_id <> "/token"

    get(url, headers: [{"token", partner_token}])
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, app_token} =
          Jason.decode!(body)
          |> then(&Caches.set(organization_id, {:app_token, app_id}, &1["token"]["token"]))

        {:ok, %{app_token: app_token}}

      {_status, _response} ->
        {:error, "invalid credentials or app id}"}
    end
  end

  @doc """
  Fetches Partner token and App Access token to get tier information for an organization with input app id
  """
  @spec get_quality_rating(non_neg_integer(), String.t()) :: {:error, any} | {:ok, map()}
  def get_quality_rating(organization_id, phone) do
    with {:ok, app_id} <- get_apps_details(organization_id, phone),
         {:ok, %{app_token: app_token}} <- get_app_token(organization_id, app_id) do
      url = @app_url <> app_id <> "/ratings"
      param = %{"phone" => phone, "isBlocked" => "true"}

      get(url, body: param, headers: [{"Authorization", app_token}])
      |> case do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          response = Jason.decode!(body)

          data = %{
            current_limit: response["currentLimit"],
            previous_limit: response["oldLimit"],
            event: response["event"]
          }

          {:ok, data}

        {_status, _response} ->
          {:error, "Invalid App Id or Phone}"}
      end
    end
  end
end
