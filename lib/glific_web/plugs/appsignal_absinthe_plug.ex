defmodule GlificWeb.Plugs.AppsignalAbsinthePlug do
  @moduledoc false

  @doc false
  def init(opts), do: opts

  @path "/api"

  @doc false
  def call(%Plug.Conn{request_path: @path, method: "POST"} = conn, _opts) do
    Appsignal.Plug.put_name(conn, "POST " <> @path)
  end

  @doc false
  def call(conn, _), do: conn
end
