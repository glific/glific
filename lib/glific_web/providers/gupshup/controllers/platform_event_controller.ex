defmodule GlificWeb.Providers.Gupshup.Controllers.PlatformEventController do
  @moduledoc """
  Acknowledges Gupshup platform events (e.g. connectivity checks). These carry no app or
  message data, so they are only counted.
  """

  use GlificWeb, :controller

  alias Glific.Providers.Gupshup.Instrumentation

  @doc """
  Counts the platform event and acknowledges it
  """
  @spec handler(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handler(conn, %{"payload" => %{"type" => type}}) do
    Instrumentation.track_platform_event(type, conn.assigns[:organization_id])

    conn
    |> Plug.Conn.send_resp(200, "")
    |> Plug.Conn.halt()
  end
end
