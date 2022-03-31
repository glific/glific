defmodule Glific.Providers.Gupshup.PartnerAPI do
  @moduledoc """
  A module to handle fetching tier related information like quality rating and app rating using partner API
  """

  alias Glific.{
    Caches,
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

  @doc """
  Fetch the stripe tax rates
  """
  @spec gupshup_partner_api :: map()
  def gupshup_partner_api,
    do: Saas.gupshup_partner_api()

  # fetches partner token
  @spec get_partner_token :: {:ok, map()} | {:error, any}
  defp get_partner_token do
    credentials = gupshup_partner_api()

    url = @partner_url <> "/login"

    # Using Cachex.get instead of Caches.get as token expire after 24hrs and we dont want to refresh the cache
    {:ok, partner_token} = Cachex.get(:glific_cache, {@global_organization_id, "partner_token"})

    if partner_token,
      do: {:ok, %{partner_token: partner_token}},
      else: do_get_partner_token(credentials["email"], credentials["password"], url)
  end

  @spec do_get_partner_token(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, any}
  defp do_get_partner_token(email, password, url) do
    post(url, %{"email" => email, "password" => password}, headers: [])
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, partner_token} =
          Jason.decode!(body)
          |> then(&Caches.set(@global_organization_id, "partner_token", &1["token"]))

        {:ok, %{partner_token: partner_token}}

      {_status, response} ->
        {:error, "invalid response #{inspect(response)}"}
    end
  end

  # fetches app id from phone using partner API
  @spec get_apps_details(non_neg_integer(), String.t()) :: {:ok, String.t()} | {:error, any}
  defp get_apps_details(organization_id, phone) do
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
