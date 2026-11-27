defmodule GlificWeb.API.V1.OnboardController do
  @moduledoc """
  The Glific Onboarding Controller
  """

  alias Glific.Saas.Onboard

  use GlificWeb, :controller

  alias Plug.Conn

  @doc false
  @spec setup(Conn.t(), map()) :: Conn.t()
  def setup(conn, %{"token" => token} = params) when is_binary(token) and token != "" do
    case Glific.verify_google_captcha(token) do
      {:ok, "success"} ->
        Map.put(params, "client_ip", Onboard.get_client_ip(conn))
        |> then(&json(conn, Onboard.setup(&1)))

      {:error, error} ->
        captcha_error(conn, error)
    end
  end

  def setup(conn, _params), do: captcha_error(conn, "Captcha token is missing")

  @doc false
  @spec reachout(Conn.t(), map()) :: Conn.t()
  def reachout(conn, %{"token" => token} = params) when is_binary(token) and token != "" do
    case Glific.verify_google_captcha(token) do
      {:ok, "success"} -> json(conn, Onboard.reachout(params))
      {:error, error} -> captcha_error(conn, error)
    end
  end

  def reachout(conn, _params), do: captcha_error(conn, "Captcha token is missing")

  @spec captcha_error(Conn.t(), String.t()) :: Conn.t()
  defp captcha_error(conn, error) do
    conn
    |> put_status(400)
    |> json(%{error: %{status: 400, message: error}})
  end
end
