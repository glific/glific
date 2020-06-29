defmodule GlificWeb.Providers.Glifproxy.Plugs.Shunt do
  @moduledoc """
   A Glifproxy shunt which will redirect all the incoming requests to the glifproxy router
   based on the event type.
  """
  alias GlificWeb.Providers.Glifproxy.Router
  alias Plug.Conn

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc false
  @spec call(
          %Plug.Conn{
            params: %{String.t() => String.t(), String.t() => %{String.t() => String.t()}}
          },
          Plug.opts()
        ) :: Plug.Conn.t()
  def call(%Conn{params: %{"type" => type, "payload" => %{"type" => payload_type}}} = conn, opts) do
    conn
    |> change_path_info(["glifproxy", type, payload_type])
    |> Router.call(opts)
  end

  @doc false
  def call(%Conn{params: %{"type" => type}} = conn, opts) do
    conn
    |> change_path_info(["glifproxy", type, "unknown"])
    |> Router.call(opts)
  end

  @doc false
  def call(conn, opts) do
    conn
    |> change_path_info(["glifproxy", "unknown", "unknown"])
    |> Router.call(opts)
  end

  @doc false
  @spec change_path_info(Plug.Conn.t(), list()) :: Plug.Conn.t()
  def change_path_info(conn, new_path),
    do: put_in(conn.path_info, new_path)
end
