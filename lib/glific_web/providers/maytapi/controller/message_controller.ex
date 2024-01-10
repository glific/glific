defmodule GlificWeb.Providers.Maytapi.Controllers.MessageController do
  @moduledoc """
  Dedicated controller to handle different types of inbound message from maytapi
  """

  use GlificWeb, :controller

  alias Glific.{
    Communications,
    Providers.Maytapi
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
    |> Maytapi.Message.receive_text()
    |> Map.put(:organization_id, conn.assigns[:organization_id])
    |> Communications.Message.receive_message()

    handler(conn, params, "text handler")
  end
end
