defmodule GlificWeb.API.V1.SessionController do
  @moduledoc """
  The Pow User Session Controller
  """

  use GlificWeb, :controller

  alias GlificWeb.APIAuthPlug
  alias Plug.Conn

  @doc false
  @spec create(Conn.t(), map()) :: Conn.t()
  def create(conn, %{"user" => user_params}) do
    conn
    |> Pow.Plug.authenticate_user(user_params)
    |> case do
      {:ok, conn} ->
        put_resp_cookie(conn, "my-cookie", %{user_id: "user"}, sign: true)
        |> json(%{
          data: %{
            access_token: conn.private[:api_access_token],
            access_token_expiry_time: conn.private[:api_access_token_expiry_time],
            renewal_token: conn.private[:api_renewal_token]
          }
        })

      {:error, conn} ->
        conn
        |> put_status(401)
        |> json(%{error: %{status: 401, message: "Invalid phone or password"}})
    end
  end

  @doc false
  @spec renew(Conn.t(), map()) :: Conn.t()
  def renew(conn, _params) do
    config = Pow.Plug.fetch_config(conn)

    conn
    |> APIAuthPlug.renew(config)
    |> case do
      {conn, nil} ->
        conn
        |> put_status(401)
        |> json(%{error: %{status: 401, message: "Invalid token"}})

      {conn, _user} ->
        json(conn, %{
          data: %{
            access_token: conn.private[:api_access_token],
            renewal_token: conn.private[:api_renewal_token]
          }
        })
    end
  end

  @doc false
  @spec delete(Conn.t(), map()) :: Conn.t()
  def delete(conn, _params) do
    conn
    |> Pow.Plug.delete()
    |> json(%{data: %{}})
  end
end
