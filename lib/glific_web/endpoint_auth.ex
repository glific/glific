defmodule GlificWeb.EndpointAuth do
  @moduledoc """
  Validating if the request comes from the gupshup or the simulator.
  """
  alias Plug.Conn

  alias Glific.{Partners, Repo}

  @behaviour Plug

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc false
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(%Conn{params: %{"app" => app_name}} = conn, _opts) do
    organization = Partners.organization(conn.assigns[:organization_id])

    if organization.services["bsp"].secrets["app_name"] == app_name do
      conn
    else
      conn
      |> put_status(401)
      |> json(%{error: %{code: 401, message: "Not authenticated"}})
    end
  end

  def call(%Conn{params: %{"payload" => %{"sender" => sender}}} = conn, _opts) do
    if sender["name"] == "Simulator" && sender["phone"] == "9876543210" do
    else
      conn
      |> put_status(401)
      |> json(%{error: %{code: 401, message: "Not authenticated"}})
    end
  end
end
