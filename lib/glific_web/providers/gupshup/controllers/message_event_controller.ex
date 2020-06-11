defmodule GlificWeb.Providers.Gupshup.Controllers.MessageEventController do
  @moduledoc """
  Dedicated controller to handle all the message status requests like read, delivered etc..
  """
  use GlificWeb, :controller

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, params, _msg) do
    json(conn, params)
  end

  @doc false
  @spec message_event(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def message_event(conn, params),
    do: handler(conn, params, "Message event handler")

  @doc false
  @spec enqueued(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def enqueued(conn, params),
    do: handler(conn, params, "enqueued handler")

  @doc false
  @spec failed(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def failed(conn, params),
    do: handler(conn, params, "failed handler")

  @doc false
  @spec sent(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sent(conn, params),
    do: handler(conn, params, "sent handler")

  @doc false
  @spec delivered(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delivered(conn, params),
    do: handler(conn, params, "delivered handler")
end
