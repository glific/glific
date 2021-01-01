defmodule GlificWeb.EndpointAuth do
  @moduledoc """
  Validating if the request comes from the gupshup or the simulator.
  """

  alias Plug.Conn

  alias Glific.Partners
  require Logger

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
    Logger.info("Invalid request: App name is incorrect: '#{app_name}'")
    end
  end

  def call(_conn, _opts) do
    Logger.info("Invalid request: Request is from unauthenticated source")
  end
end
