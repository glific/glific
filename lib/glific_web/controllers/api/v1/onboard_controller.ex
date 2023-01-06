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

      {:error, _error} ->
        conn
        |> put_status(400)
        |> json(%{error: %{status: 400, message: "Error while setting up NGO"}})
    end
  end
end
