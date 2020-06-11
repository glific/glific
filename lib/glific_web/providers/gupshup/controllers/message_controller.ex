defmodule GlificWeb.Providers.Gupshup.Controllers.MessageController do
  @moduledoc """
  Dedicated controller to handle different types of inbound message form Gupshup
  """

  use GlificWeb, :controller

  alias Glific.Communications.Message, as: Communications
  alias Glific.Providers.Gupshup.Message, as: GupshupMessage

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, params, _msg) do
    json(conn, nil)
  end

  @doc false
  @spec message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def message(conn, params),
    do: handler(conn, params, "message handler")

  @doc false
  @spec text(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def text(conn, params) do
    GupshupMessage.receive_text(params)
    |> Communications.receive_text()

    handler(conn, params, "text handler")
  end

  @doc false
  @spec image(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def image(conn, params) do
    GupshupMessage.receive_media(params)
    |> Map.merge(%{type: :image})
    |> Communications.receive_media()

    handler(conn, params, "image handler")
  end

  @doc false
  @spec file(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def file(conn, params) do
    GupshupMessage.receive_media(params)
    |> Map.merge(%{type: :document})
    |> Communications.receive_media()

    handler(conn, params, "file handler")
  end

  @doc false
  @spec audio(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def audio(conn, params) do
    GupshupMessage.receive_media(params)
    |> Map.merge(%{type: :audio})
    |> Communications.receive_media()

    handler(conn, params, "file handler")
  end

  @doc false
  @spec video(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def video(conn, params) do
    GupshupMessage.receive_media(params)
    |> Map.merge(%{type: :video})
    |> Communications.receive_media()

    handler(conn, params, "file handler")
  end
end
