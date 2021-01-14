defmodule GlificWeb.API.V1.CorsController do
  @moduledoc """
   Controller to manage the CORS request from the frontend.
  """

  use GlificWeb, :controller
  require Logger
  import Glific.CorsProxy, only: [request: 4, write_response: 2]

  @doc false
  @spec get(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def get(conn, params) do
    :get
    |> request(params["url"], conn.req_headers, "")
    |> write_response(conn)
  end
end
