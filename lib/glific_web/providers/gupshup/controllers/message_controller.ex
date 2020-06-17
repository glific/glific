defmodule GlificWeb.Providers.Gupshup.Controllers.MessageController do
  @moduledoc """
  Dedicated controller to handle different types of inbound message form Gupshup
  """

  use GlificWeb, :controller

  alias Glific.Communications.Message, as: Communications
  alias Glific.Providers.Gupshup.Message, as: GupshupMessage

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, msg) do
    IO.puts(msg)
    json(conn, nil)
  end

  @doc false
  @spec message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def message(conn, params) do
    handler(conn, params, "message handler")
  end

  @doc false
  @spec text(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def text(conn, params) do
    GupshupMessage.receive_text(params)
    |> Communications.receive_text()

    handler(conn, params, "text handler")
  end

  @doc false
  @spec image(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def image(conn, params), do: media(conn, params, %{type: :image})

  @doc false
  @spec file(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def file(conn, params), do: media(conn, params, %{type: :document})

  @doc false
  @spec audio(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def audio(conn, params), do: media(conn, params, %{type: :audio})

  @doc false
  @spec video(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def video(conn, params), do: media(conn, params, %{type: :video})

  @doc false
  @spec media(Plug.Conn.t(), map(), map()) :: Plug.Conn.t()
  defp media(conn, params, type) do
    GupshupMessage.receive_media(params)
    |> Map.merge(type)
    |> Communications.receive_media()

    handler(conn, params, "media handler")
  end
end
