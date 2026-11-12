defmodule GlificWeb.Providers.Gupshup.Controllers.V3.CallbackController do
  @moduledoc """
  Single entry point for Gupshup V3 (Meta format) callbacks. Each change is handled by
  `Glific.Providers.Gupshup.V3.Dispatcher`.
  """
  use GlificWeb, :controller

  alias Glific.Providers.Gupshup.V3.Dispatcher

  @doc """
  Handles every change in a V3 callback
  """
  @spec callback(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def callback(conn, %{"entry" => entries}) do
    Dispatcher.dispatch(entries, conn.assigns[:organization_id])

    conn
    |> Plug.Conn.send_resp(200, "")
    |> Plug.Conn.halt()
  end
end
