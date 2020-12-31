defmodule GlificWeb.Providers.Gupshup.Plugs.Shunt do
  @moduledoc """
  A Gupshup shunt which will redirect all the incoming requests to the gupshup router based on there event type.
  """

  alias Plug.Conn

  alias Glific.{Partners, Repo}
  alias GlificWeb.Providers.Gupshup.Router

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc """
  Build the context with the root user for all gupshup calls, this
  gives us permission to update contacts etc
  """
  @spec build_context(Conn.t()) :: nil
  def build_context(conn) do
    organization = Partners.organization(conn.assigns[:organization_id])
    Repo.put_current_user(organization.root_user)
  end

  @doc false
  @spec call(
          %Plug.Conn{
            params: %{String.t() => String.t(), String.t() => %{String.t() => String.t()}}
          },
          Plug.opts()
        ) :: Plug.Conn.t()
  def call(%Conn{params: %{"app" => app_name, "type" => type, "payload" => %{"type" => payload_type}}} = conn, opts) do
    organization = Partners.organization(conn.assigns[:organization_id])
    if organization.services["bsp"].secrets["app_name"] == app_name do
      build_context(conn)
      conn
      |> change_path_info(["gupshup", type, payload_type])
      |> Router.call(opts)
    else
      call(conn, opts)
    end
  end

  def call(%Conn{params: %{"type" => type, "payload" => %{"type" => payload_type, "sender" => sender}}} = conn, opts) do
    if sender["name"] == "Simulator" && sender["phone"] == "9876543210" do
      build_context(conn)

      conn
      |> change_path_info(["gupshup", type, payload_type])
      |> Router.call(opts)
    else
      call(conn, opts)
    end
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
  @spec change_path_info(Plug.Conn.t(), list()) :: Plug.Conn.t()
  def change_path_info(conn, new_path),
    do: put_in(conn.path_info, new_path)
end
