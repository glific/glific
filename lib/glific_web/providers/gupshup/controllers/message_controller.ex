defmodule GlificWeb.Provider.Controllers.GupshupMessageController do
  use GlificWeb, :controller

  alias TwoWay.Communications.BSP.Gupshup.Message, as: GupshupMessage
  alias TwoWay.Communications.Message, as: Communications

  def handler(conn, params, msg) do
    IO.puts(msg)
    IO.inspect(params)
    json(conn, nil)
  end

  def message(conn, params),
    do: handler(conn, params, "message handler")

  def text(conn, params) do
    # GupshupMessage.receive_text(params)
    # |> Communications.receive_text()

    handler(conn, params, "text handler")
  end

  def image(conn, params) do
    GupshupMessage.receive_media(params)
    |> Map.merge(%{type: :image})
    |> Communications.receive_media()

    handler(conn, params, "image handler")
  end

  def file(conn, params) do
    GupshupMessage.receive_media(params)
    |> Map.merge(%{type: :document})
    |> Communications.receive_media()

    handler(conn, params, "file handler")
  end

  def audio(conn, params) do
    GupshupMessage.receive_media(params)
    |> Map.merge(%{type: :audio})
    |> Communications.receive_media()

    handler(conn, params, "file handler")
  end

  def video(conn, params) do
    GupshupMessage.receive_media(params)
    |> Map.merge(%{type: :video})
    |> Communications.receive_media()

    handler(conn, params, "file handler")
  end

  def contact(conn, params),
    do: handler(conn, params, "contact handler")

  def location(conn, params),
    do: handler(conn, params, "location handler")
end
