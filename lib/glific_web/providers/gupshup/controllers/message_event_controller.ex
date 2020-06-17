defmodule GlificWeb.Providers.Gupshup.Controllers.MessageEventController do
  @moduledoc """
  Dedicated controller to handle all the message status requests like read, delivered etc..
  """
  use GlificWeb, :controller

  alias Glific.Communications.Message, as: Communications

  @doc """
  Default handle for all message event callbacks
  """
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    json(conn, nil)
  end

  @doc false
  @spec message_event(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def message_event(conn, params),
    do: update_status(conn, params, :enqueued)

  @doc false
  @spec enqueued(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def enqueued(conn, params),
    do: update_status(conn, params, :enqueued)

  @doc false
  @spec failed(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def failed(conn, params),
    do: update_status(conn, params, :failed)

  @doc false
  @spec sent(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sent(conn, params),
    do: update_status(conn, params, :sent)

  @doc false
  @spec delivered(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delivered(conn, params),
    do: update_status(conn, params, :delivered)

  @doc false
  @spec read(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def read(conn, params),
    do: update_status(conn, params, :read)

  # Updates the provider message status based on provider message id
  @spec update_status(Plug.Conn.t(), map(), atom()) :: Plug.Conn.t()
  defp update_status(conn, params, status) do
    provider_message_id = get_in(params, ["payload", "gsId"]) || get_in(params, ["payload", "id"])
    Communications.update_provider_status(provider_message_id, status)
    handler(conn, params, "Status updated")
  end
end
