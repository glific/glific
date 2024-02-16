defmodule GlificWeb.Providers.Maytapi.Plugs.Shunt do
  @moduledoc """
  A Maytapi shunt which will redirect all the incoming requests to the maytapi router based on there event type.
  """

  alias Plug.Conn

  alias Glific.{Appsignal, Partners, Partners.Organization, Repo}
  alias GlificWeb.Providers.Maytapi.Router

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc """
  Build the context with the root user for all maytapi calls, this
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
  def call(%Conn{params: %{"message" => %{"type" => payload_type}}} = conn, opts) do
    organization = build_context(conn)

    path =
      ["maytapi"] ++
        if Glific.safe_string_to_atom(organization.status) == :active,
          do: ["message", payload_type],
          else: ["not_active"]

    conn
    |> change_path_info(path)
    |> Router.call(opts)
  end

  @doc false
  def call(%Conn{params: %{"response" => _response}} = conn, opts) do
    organization = build_context(conn)

    path =
      ["maytapi"] ++
        if Glific.safe_string_to_atom(organization.status) == :active,
          do: ["message-event", "handler"],
          else: ["not_active"]

    conn
    |> change_path_info(path)
    |> Router.call(opts)
  end

  @doc false
  def call(conn, opts) do
    conn
    |> change_path_info(["maytapi", "unknown", "unknown"])
    |> Router.call(opts)
  end

  @doc false
  @spec change_path_info(Plug.Conn.t(), list()) :: Plug.Conn.t()
  def change_path_info(conn, new_path) do
    Appsignal.set_namespace("maytapi_webhooks")
    put_in(conn.path_info, new_path)
  end
end
