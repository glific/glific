defmodule GlificWeb.Providers.Gupshup.Controllers.MessageEventController do
  use GlificWeb, :controller

  def handler(conn, params, msg) do
    IO.puts(msg)
    IO.inspect(params)
    json(conn, nil)
  end

  def message_event(conn, params),
    do: handler(conn, params, "Message event handler")

  def enqueued(conn, params),
    do: handler(conn, params, "enqueued handler")

  def failed(conn, params),
    do: handler(conn, params, "failed handler")

  def sent(conn, params),
    do: handler(conn, params, "sent handler")

  def delivered(conn, params),
    do: handler(conn, params, "delivered handler")
end
