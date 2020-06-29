defmodule GlificWeb.Providers.Glifproxy.Controllers.MessageController do
  @moduledoc """
  Dedicated controller to handle different types of inbound message form Glifproxy
  """

  use GlificWeb, :controller

  alias Glific.{
    Communications,
    Providers.Glifproxy
  }

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    json(conn, nil)
  end

  @doc """
  Parse text message payload and convert that into Glific message struct
  """
  @spec text(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def text(conn, params) do
    Glifproxy.Message.receive_text(params)
    |> Communications.Message.receive_message()

    handler(conn, params, "text handler")
  end

  @doc """
  Callback for glifproxy image images
  """
  @spec image(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def image(conn, params), do: media(conn, params, :image)

  @doc """
  Callback file glifproxy image images
  """
  @spec file(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def file(conn, params), do: media(conn, params, :document)

  @doc """
  Callback audio glifproxy image images
  """
  @spec audio(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def audio(conn, params), do: media(conn, params, :audio)

  @doc """
  Callback video glifproxy image images
  """
  @spec video(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def video(conn, params), do: media(conn, params, :video)

  @doc false
  # Handle Glifproxy media message and convert them into Glific Message struct
  @spec media(Plug.Conn.t(), map(), atom()) :: Plug.Conn.t()
  defp media(conn, params, type) do
    Glifproxy.Message.receive_media(params)
    |> Communications.Message.receive_message(type)

    handler(conn, params, "media handler")
  end
end
