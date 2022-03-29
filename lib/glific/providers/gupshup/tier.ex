defmodule Glific.Providers.Gupshup.Tier do
  @moduledoc """
  A common worker to handle send message processes irrespective of BSP
  Glific.Providers.Gupshup.Tier.get_app_token
  """
  alias Plug.Conn.Query

  use Tesla
  plug Tesla.Middleware.Logger

  plug Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1

  @partner_url "https://partner.gupshup.io/partner/account/login"
  @app_url "https://partner.gupshup.io/partner/app/"

  @spec get_partner_token :: {:ok, map()} | {:error, any}
  def get_partner_token() do
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

  @spec get_app_token :: {:ok, map()} | {:error, any}
  def get_app_token() do
    with {:ok, %{partner_token: partner_token}} <- get_partner_token() do
      url = @app_url <> "59e80ba8-1d57-4cb9-8598-7f767e37c6cc" <> "/token"

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

  @spec get_tier_info(String.t(), String.t()) :: {:error, any} | {:ok, map()}
  def get_tier_info(app_id, phone) do
    with {:ok, %{app_token: app_token}} <- get_app_token() do
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
