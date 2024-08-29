defmodule GlificWeb.Providers.Maytapi.Controllers.StatusController do
  @moduledoc """
  Dedicated controller to handle the status of phone from maytapi
  """

  use GlificWeb, :controller

  # alias Glific.{
  #   Providers.Maytapi
  # }

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, params, msg) do
    IO.inspect(conn)
    IO.inspect(params)
    IO.inspect(msg)
    conn
    |> Plug.Conn.send_resp(200, "")
    |> Plug.Conn.halt()
  end

  @doc """
  Parse text message payload and convert that into Glific message struct
  """
  # @spec status(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def status(conn, params) do
    params
    |> IO.inspect()

    handler(conn, params, "status handler")
  end
end
