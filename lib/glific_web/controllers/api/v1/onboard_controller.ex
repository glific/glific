defmodule GlificWeb.API.V1.OnboardController do
  @moduledoc """
  The Glific Onboarding Controller
  """

  alias Glific.{
    Partners,
    Partners.Organization,
    Repo,
    Saas.Onboard
  }

  use GlificWeb, :controller

  alias Plug.Conn

  @doc false
  @spec setup(Conn.t(), map()) :: Conn.t()
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
  def update_registration(conn, %{"org_id" => org_id} = params) do
    case Partners.organization(String.to_integer(org_id)) do
      %Organization{root_user: root_user} = org ->
        Repo.put_current_user(root_user)
        json(conn, Onboard.update_registration(params, org))

      _ ->
        conn
        |> put_status(400)
        |> json(%{error: %{status: 400, message: "Organization with ID #{org_id} doesn't exist"}})
    end
  end

  def update_registration(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: %{status: 400, message: "org_id is empty"}})
  end

  @doc false
  @spec reachout(Conn.t(), map()) :: Conn.t()
  def reachout(conn, params) do
    json(conn, Onboard.reachout(params))
  end
end
