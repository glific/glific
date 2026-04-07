defmodule GlificWeb.DifyAuthPlug do
  @moduledoc """
  Plug that authenticates requests from Dify using a shared API key
  sent in the `x-dify-api-key` header.
  """

  import Plug.Conn

  @behaviour Plug

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc false
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(conn, _opts) do
    expected_key = Application.get_env(:glific, :dify_callback_api_key, "")

    with [provided_key] <- get_req_header(conn, "x-dify-api-key"),
         true <- expected_key != "" and Plug.Crypto.secure_compare(provided_key, expected_key) do
      conn
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Unauthorized"}))
        |> halt()
    end
  end
end
