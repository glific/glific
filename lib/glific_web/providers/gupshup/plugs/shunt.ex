defmodule GlificWeb.Providers.Gupshup.Plugs.Shunt do
  @moduledoc """
  A Gupshup shunt which will redirect all the incoming requests to the gupshup router based on there event type.
  """

  alias Plug.Conn

  alias Glific.{Appsignal, Partners, Partners.Organization, Repo}
  alias GlificWeb.Providers.Gupshup.Router

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
  def call(%Conn{params: %{"type" => type, "payload" => %{"type" => payload_type}}} = conn, opts) do
    path = active_path(conn, [type, payload_type])

    conn
    |> change_path_info(path)
    |> Router.call(opts)
  end

  @doc false
  def call(
        %Conn{params: %{"type" => type, "payload" => %{"deductions" => _deductions}}} = conn,
        opts
      ) do
    path = active_path(conn, [type, "conversations"])

    conn
    |> change_path_info(path)
    |> Router.call(opts)
  end

  @doc false
  def call(%Conn{params: %{"entry" => entries}} = conn, opts)
      when is_list(entries) do
    path =
      case entry_route(entries) do
        nil -> ["gupshup", "entry", "unknown"]
        route -> active_path(conn, route)
      end

    conn
    |> change_path_info(path)
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

  @spec active_path(Conn.t(), [String.t()]) :: [String.t()]
  defp active_path(conn, route) do
    organization = build_context(conn)

    if Glific.safe_string_to_atom(organization.status) == :active,
      do: ["gupshup" | route],
      else: ["gupshup", "not_active_or_approved"]
  end

  @spec entry_route([map()]) :: [String.t()] | nil
  defp entry_route(entries) do
    # A payload is routed to a single handler; Meta sends inbound messages and statuses
    # as separate notifications, so a form reply wins if both ever arrive together
    cond do
      nfm_reply_message?(entries) -> ["message", "whatsapp_form_response"]
      status_update?(entries) -> ["message-event", "statuses"]
      true -> nil
    end
  end

  @spec nfm_reply_message?(list()) :: boolean()
  defp nfm_reply_message?([%{"changes" => [change | _]} | _]) do
    case change do
      %{"value" => %{"messages" => [%{"interactive" => %{"type" => "nfm_reply"}} | _]}} ->
        true

      _ ->
        false
    end
  end

  defp nfm_reply_message?(_), do: false

  @spec status_update?(list()) :: boolean()
  defp status_update?(entries) do
    Enum.any?(entries, fn
      %{"changes" => changes} when is_list(changes) ->
        Enum.any?(changes, &match?(%{"value" => %{"statuses" => [_ | _]}}, &1))

      _ ->
        false
    end)
  end

  @doc false
  @spec change_path_info(Plug.Conn.t(), list()) :: Plug.Conn.t()
  def change_path_info(conn, new_path) do
    ## setting up appsignal namespace so that we can ignore this
    Appsignal.set_namespace("gupshup_webhooks")
    put_in(conn.path_info, new_path)
  end
end
