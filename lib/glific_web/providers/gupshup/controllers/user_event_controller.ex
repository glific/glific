defmodule GlificWeb.Providers.Gupshup.Controllers.UserEventController do
  @moduledoc """
  Dedicated controller to handle different types of user events requests like optin an optout form
  """
  use GlificWeb, :controller

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    json(conn, nil)
  end

  @doc false
  @spec opted_in(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def opted_in(conn, params) do
    {:ok, timestamp} = DateTime.from_unix(params["timestamp"], :millisecond)

    get_in(params, ["payload", "phone"])
    |> Glific.Contacts.contact_opted_in(timestamp)

    handler(conn, params, "Opted in handler")
  end

  @doc false
  @spec opted_out(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def opted_out(conn, params) do
    {:ok, timestamp} = DateTime.from_unix(params["timestamp"], :millisecond)
    get_in(params, ["payload", "phone"])
    |> Glific.Contacts.contact_opted_out(timestamp)

     handler(conn, params, "Opted out handler")

  end
end
