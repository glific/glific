defmodule GlificWeb.Providers.Gupshup.Enterprise.Plugs.Shunt do
  @moduledoc """
  A Gupshup shunt which will redirect all the incoming requests to the gupshup router based on there event type.
  """

  alias Plug.Conn

  alias Glific.{Partners, Partners.Organization, Repo}
  alias GlificWeb.Providers.Gupshup.Enterprise.Router

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc """
  Build the context with the root user for all gupshup calls, this
  gives us permission to update contacts etc
  """
  @spec build_context(Conn.t()) :: Organization.t()
  def build_context(conn) do
    organization = Partners.organization(conn.assigns[:organization_id])
    Repo.put_current_user(organization.root_user)
    organization
  end

  @doc false
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(%Conn{params: %{"type" => payload_type}} = conn, opts) do
    IO.inspect("debug001shunt")
    IO.inspect(conn)
    IO.inspect(payload_type)
    IO.inspect(opts)
    organization = build_context(conn)

    path =
      ["gupshup"] ++
        if Glific.safe_string_to_atom(organization.status) == :active,
          do: ["message", payload_type],
          else: ["not_active_or_approved"]

    conn
    |> change_path_info(path)
    |> Router.call(opts)
  end

  @doc false
  @spec change_path_info(Plug.Conn.t(), list()) :: Plug.Conn.t()
  def change_path_info(conn, new_path),
    do: put_in(conn.path_info, new_path)
end
