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

  @spec gupshup :: {:error, any} | {:ok, Tesla.Env.t()}
  def gupshup() do
    with {:ok, %{app_token: app_token}} <- get_app_token() do
      url = @app_url <> "59e80ba8-1d57-4cb9-8598-7f767e37c6cc" <> "/ratings"
      param = %{"phone" => "918904910794", "isBlocked" => "true"}

      get(url,
        body: param,
        headers: [{"Authorization", app_token}]
      )
    end
  end
end
