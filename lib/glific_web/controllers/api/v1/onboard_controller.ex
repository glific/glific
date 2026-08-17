defmodule GlificWeb.API.V1.OnboardController do
  @moduledoc """
  The Glific Onboarding Controller
  """

  alias Glific.Saas.Onboard

  use GlificWeb, :controller

  alias Plug.Conn

  @doc false
  def setup(conn, %{"token" => token} = params) do
    case Glific.verify_google_captcha(token) do
      {:ok, "success"} ->
        Map.put(params, "client_ip", Onboard.get_client_ip(conn))
        |> then(&json(conn, Onboard.setup(&1)))

      {:error, error} ->
        conn
        |> put_status(400)
        |> json(%{error: %{status: 400, message: error}})
    end
  end

  @doc false
  @spec update_registration(Conn.t(), map()) :: Conn.t()
  def update_registration(conn, params) do
    response = Onboard.update_registration(params)

    if Map.get(response, :is_valid, true) do
      json(conn, response)
    else
      conn
      |> put_status(400)
      |> json(%{
        error: %{
          status: 400,
          message: Map.get(response, :error),
          messages: Map.get(response, :messages, %{}),
          is_valid: false
        }
      })
    end
  end

  @doc false
  @spec reachout(Conn.t(), map()) :: Conn.t()
  def reachout(conn, params) do
    json(conn, Onboard.reachout(params))
  end
end
