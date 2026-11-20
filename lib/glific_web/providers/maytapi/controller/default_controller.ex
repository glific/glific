defmodule GlificWeb.Providers.Maytapi.Controllers.DefaultController do
  @moduledoc false

  use GlificWeb, :controller

  alias Glific.Providers.Maytapi.Instrumentation

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    json(conn, nil)
  end

  @doc false
  @spec unknown(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def unknown(conn, params) do
    Instrumentation.track_receive(
      "unhandled:" <> Enum.join(List.wrap(params["unknown"]), "/"),
      conn.assigns[:organization_id]
    )

    handler(conn, params, "unknown handler")
  end
end
