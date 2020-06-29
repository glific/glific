defmodule GlificWeb.Providers.Glifproxy.Controllers.DefaultController do
  @moduledoc false

  use GlificWeb, :controller

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    json(conn, nil)
  end

  @doc false
  @spec unknown(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def unknown(conn, params),
    do: handler(conn, params, "unknown handler")
end
