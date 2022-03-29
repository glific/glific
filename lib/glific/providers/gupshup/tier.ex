defmodule Glific.Providers.Gupshup.Tier do
  @moduledoc """
  A module to handle fetching tier related information like quality rating and app rating
  """

  alias Plug.Conn.Query

  use Tesla
  plug(Tesla.Middleware.Logger)

  plug(Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1
  )

  @partner_url "https://partner.gupshup.io/partner/account/login"
  @app_url "https://partner.gupshup.io/partner/app/"

  # fetches partner token
  @spec get_partner_token :: {:ok, map()} | {:error, any}
  defp get_partner_token do
    email = Application.fetch_env!(:glific, :gupshup_partner_email)
    password = Application.fetch_env!(:glific, :gupshup_partner_password)

    post(@partner_url, %{"email" => email, "password" => password}, headers: [])
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)
        |> then(&{:ok, %{partner_token: &1["token"]}})

      {_status, response} ->
        {:error, "invalid response #{inspect(response)}"}
    end
  end

  # fetches partner token first to get app access token
  @spec get_app_token(String.t()) :: {:ok, map()} | {:error, any}
  defp get_app_token(app_id) do
    with {:ok, %{partner_token: partner_token}} <- get_partner_token() do
      url = @app_url <> app_id <> "/token"

      get(url, headers: [{"token", partner_token}])
      |> case do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          Jason.decode!(body)
          |> then(&{:ok, %{app_token: &1["token"]["token"]}})

        {_status, _response} ->
          {:error, "invalid credentials or app id}"}
      end
    end
  end

  @doc """
  Fetches Partner token and App Access token to get tier information for an organization with input app id
  """
  @spec get_quality_rating_info(String.t(), String.t()) :: {:error, any} | {:ok, map()}
  def get_quality_rating_info(app_id, phone) do
    with {:ok, %{app_token: app_token}} <- get_app_token(app_id) do
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
