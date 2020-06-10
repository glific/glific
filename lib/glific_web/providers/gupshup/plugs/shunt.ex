defmodule GlificWeb.Providers.Gupshup.Plugs.Shunt do
  @moduledoc """
   A Gupshup shunt which will redirect all the incoming requests to the gupshup router based on there event type.
  """

  alias Plug.Conn
  alias GlificWeb.Providers.Gupshup.Router

  @doc false
  @spec init(Plug.opts) :: Plug.opts
  def init(opts), do: opts

  @doc false
  @spec call(%Plug.Conn{params: %{String.t() => String.t(), String.t() => %{String.t() => String.t()}}}, Plug.opts) :: Plug.Conn.t
  def call(%Conn{params: %{"type" => type, "payload" => %{"type" => payload_type}}} = conn, opts) do
    conn
    |> change_path_info(["gupshup", type, payload_type])
    |> Router.call(opts)
  end

  @doc false
  def call(%Conn{params: %{"type" => type}} = conn, opts) do
    conn
    |> change_path_info(["gupshup", type, "unknown"])
    |> Router.call(opts)
  end

  @doc false
  def call(conn, opts) do
    conn
    |> change_path_info(["gupshup", "unknown", "unknown"])
    |> Router.call(opts)
  end

  @doc false
  @spec change_path_info(Plug.Conn.t(), list()) :: Plug.Conn.t
  def change_path_info(conn, new_path),
    do: put_in(conn.path_info, new_path)
end
