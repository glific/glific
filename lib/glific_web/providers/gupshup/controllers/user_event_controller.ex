defmodule GlificWeb.Providers.Gupshup.Controllers.UserEventController do
  @moduledoc """
  Dedicated controller to handle different types of user events requests like optin an optout form
  """
  use GlificWeb, :controller
  require Logger

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    conn
    |> Plug.Conn.send_resp(200, "")
    |> Plug.Conn.halt()
  end

  @doc false
  @spec opted_in(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def opted_in(conn, params) do
    {:ok, timestamp} = DateTime.from_unix(params["timestamp"], :millisecond)

    Glific.Contacts.contact_opted_in(
      :whatsapp,
      get_in(params, ["payload", "phone"]),
      %{organization_id: conn.assigns[:organization_id]},
      utc_time: timestamp,
      method: "BSP"
    )

    phone_number =
      params
      |> get_in(["payload", "phone"])
      |> Glific.mask_phone_number()

    Logger.info("Contact with phone: #{phone_number} opted in on #{timestamp}")

    handler(conn, params, "Opted in handler")
  end

  @doc false
  @spec opted_out(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def opted_out(conn, params) do
    {:ok, timestamp} = DateTime.from_unix(params["timestamp"], :millisecond)

    Glific.Contacts.contact_opted_out(
      :whatsapp,
      get_in(params, ["payload", "phone"]),
      conn.assigns[:organization_id],
      timestamp,
      "BSP"
    )

    phone_number =
      params
      |> get_in(["payload", "phone"])
      |> Glific.mask_phone_number()

    Logger.info("Contact with phone: #{phone_number} opted out on #{timestamp}")

    handler(conn, params, "Opted out handler")
  end
end
