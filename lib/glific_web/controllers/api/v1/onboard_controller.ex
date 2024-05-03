defmodule GlificWeb.API.V1.OnboardController do
  @moduledoc """
  The Glific Onboarding Controller
  """

  use GlificWeb, :controller
  require Logger

  alias Glific.Saas.Onboard
  alias Plug.Conn

  @doc false
  @spec setup(Conn.t(), map()) :: Conn.t()
  def setup(conn, %{"token" => token} = params) do
    case Glific.verify_google_captcha(token) do
      {:ok, "success"} ->
        json(conn, Onboard.setup(params))

      {:error, error} ->
        conn
        |> put_status(400)
        |> json(%{error: %{status: 400, message: error}})
    end
  end

  @doc false
  @spec update_registration(Conn.t(), map()) :: Conn.t()
  def update_registration(conn, params) do
    json(conn, Onboard.update_registration(params))
  end

  @doc false
  @spec reachout(Conn.t(), map()) :: Conn.t()
  def reachout(conn, params) do
    json(conn, Onboard.reachout(params))
  end
end
