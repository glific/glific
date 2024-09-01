defmodule GlificWeb.Providers.Maytapi.Controllers.StatusController do
  @moduledoc false

  use GlificWeb, :controller
  alias Glific.Providers.Maytapi.ApiClient

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    conn
    |> Plug.Conn.send_resp(200, "")
    |> Plug.Conn.halt()
  end

  @doc false
  @spec status(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def status(conn, %{"status" => status, "phone_id" => phone_id} = params) do
    ApiClient.status(status, phone_id)

    handler(conn, params, "status handler")
  end
end
