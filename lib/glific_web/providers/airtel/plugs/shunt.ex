defmodule GlificWeb.Providers.Airtel.Plugs.Shunt do
  @moduledoc """
  A Airtel shunt which will redirect all the incoming requests to the airtel router based on there event type.
  """

  alias Plug.Conn

  alias Glific.{Appsignal, Partners, Partners.Organization, Repo}
  alias GlificWeb.Providers.Airtel.Router

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc """
  Build the context with the root user for all airtel calls, this
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
  def call(%Conn{params: %{"type" => type, "payload" => %{"type" => payload_type}}} = conn, opts) do
    organization = build_context(conn)

    path =
      ["airtel"] ++
        if Glific.safe_string_to_atom(organization.status) == :active,
          do: [type, payload_type],
          else: ["not_active_or_approved"]

    conn
    |> change_path_info(path)
    |> Router.call(opts)
  end

  @doc false
  def call(
        %Conn{params: %{"type" => type, "payload" => %{"deductions" => _deductions}}} = conn,
        opts
      ) do
    organization = build_context(conn)

    path =
      ["airtel"] ++
        if Glific.safe_string_to_atom(organization.status) == :active,
          do: [type, "conversations"],
          else: ["not_active_or_approved"]

    conn
    |> change_path_info(path)
    |> Router.call(opts)
  end

  @doc false
  def call(%Conn{params: %{"message" => %{"type" => type}}} = conn, opts) do
    organization = build_context(conn)

    path =
      ["airtel"] ++
        if Glific.safe_string_to_atom(organization.status) == :active,
          do: ["message", type],
          else: ["not_active_or_approved"]

    conn
    |> change_path_info(path)
    |> Router.call(opts)
  end

  @doc false
  def call(conn, opts) do
    conn
    |> change_path_info(["airtel", "unknown", "unknown"])
    |> IO.inspect()
    |> Router.call(opts)
  end

  @doc false
  @spec change_path_info(Plug.Conn.t(), list()) :: Plug.Conn.t()
  def change_path_info(conn, new_path) do
    ## setting up appsignal namespace so that we can ignore this
    Appsignal.set_namespace("airtel_webhooks")
    put_in(conn.path_info, new_path)
  end
end
