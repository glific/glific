defmodule GlificWeb.Providers.Gupshup.Controllers.UserEventController do
  use GlificWeb, :controller

  def handler(conn, params, msg) do
    IO.puts(msg)
    IO.inspect(params)
    json(conn, nil)
  end

  def user_event(conn, params),
    do: handler(conn, params, "User event handler")

  def sandbox_start(conn, params),
    do: handler(conn, params, "Sandbox start handler")

  def opted_in(conn, params),
    do: handler(conn, params, "Opted in handler")

  def opted_out(conn, params),
    do: handler(conn, params, "Opted out handler")
end
