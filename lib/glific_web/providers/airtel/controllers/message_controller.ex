defmodule GlificWeb.Providers.Airtel.Controllers.MessageController do
  @moduledoc """
  Dedicated controller to handle different types of inbound message from Airtel
  """

  use GlificWeb, :controller

  alias Glific.{
    Communications,
    Providers.Airtel
  }

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    conn
    |> Plug.Conn.send_resp(200, "")
    |> Plug.Conn.halt()
  end

  @doc """
  Parse text message payload and convert that into Glific message struct
  """
  @spec text(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def text(conn, params) do
    params
    |> Airtel.Message.receive_text()
    |> Map.put(:organization_id, conn.assigns[:organization_id])
    |> Communications.Message.receive_message()

    handler(conn, params, "text handler")
  end

  @doc """
  Callback for airtel image type
  """
  @spec image(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def image(conn, params), do: media(conn, params, :image)

  @doc """
  Callback for airtel file type
  """
  @spec file(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def file(conn, params), do: media(conn, params, :document)

  @doc """
  Callback for airtel audio type
  """
  @spec audio(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def audio(conn, params), do: media(conn, params, :audio)

  @doc """
  Callback for airtel video type
  """
  @spec video(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def video(conn, params), do: media(conn, params, :video)

  @doc """
  Callback for airtel sticker image
  """
  @spec sticker(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sticker(conn, params), do: media(conn, params, :sticker)

  @doc false
  # Handle Airtel media message and convert them into Glific Message struct
  @spec media(Plug.Conn.t(), map(), atom()) :: Plug.Conn.t()
  defp media(conn, params, type) do
    params
    |> Airtel.Message.receive_media()
    |> Map.put(:organization_id, conn.assigns[:organization_id])
    |> Communications.Message.receive_message(type)

    handler(conn, params, "media handler")
  end

  @doc """
  Callback for interactive quick reply type
  """
  @spec quick_reply(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def quick_reply(conn, params), do: interactive(conn, params, :quick_reply)

  @doc """
  Callback for interactive list
  """
  @spec list(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list(conn, params), do: interactive(conn, params, :list)

  @doc false
  # Handle Airtel interactive message and convert them into Glific Message struct
  @spec interactive(Plug.Conn.t(), map(), atom()) :: Plug.Conn.t()
  defp interactive(conn, params, type) do
    params
    |> Airtel.Message.receive_interactive()
    |> Map.put(:organization_id, conn.assigns[:organization_id])
    |> Communications.Message.receive_message(type)

    handler(conn, params, "interactive handler")
  end

  @doc false
  # Handle Airtel location message and convert them into Glific Message struct
  @spec location(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def location(conn, params) do
    params
    |> Airtel.Message.receive_location()
    |> Map.put(:organization_id, conn.assigns[:organization_id])
    |> Communications.Message.receive_message(:location)

    handler(conn, params, "location handler")
  end
end
