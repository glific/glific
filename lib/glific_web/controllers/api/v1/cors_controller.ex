defmodule GlificWeb.API.V1.CorsController do
  use GlificWeb, :controller
  require Logger
  import Glific.CorsProxy, only: [request: 4, write_response: 2, put_access_control_headers: 1]

  def get(conn, params) do
    :get
    |> request(params["url"], conn.req_headers, "")
    |> write_response(conn)
  end
end
