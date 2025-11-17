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
    organization = build_context(conn)

    path =
      ["gupshup"] ++
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
      ["gupshup"] ++
        if Glific.safe_string_to_atom(organization.status) == :active,
          do: [type, "conversations"],
          else: ["not_active_or_approved"]

    conn
    |> change_path_info(path)
    |> Router.call(opts)
  end

  @doc false
  def call(%Conn{params: %{"entry" => entries}} = conn, opts)
      when is_list(entries) do
    if nfm_reply_message?(entries) do
      organization = build_context(conn)

      path =
        ["gupshup"] ++
          if Glific.safe_string_to_atom(organization.status) == :active,
            do: ["message", "whatsapp_form_response"],
            else: ["not_active_or_approved"]

      conn
      |> change_path_info(path)
      |> Router.call(opts)
    else
      conn
      |> change_path_info(["gupshup", "entry", "unknown"])
      |> Router.call(opts)
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

  defp nfm_reply_message?([%{"changes" => [change | _]} | _]) do
    case change do
      %{"value" => %{"messages" => [%{"interactive" => %{"type" => "nfm_reply"}} | _]}} ->
        true

      _ ->
        false
    end
  end

  defp nfm_reply_message?(_), do: false

  @doc false
  @spec change_path_info(Plug.Conn.t(), list()) :: Plug.Conn.t()
  def change_path_info(conn, new_path) do
    ## setting up appsignal namespace so that we can ignore this
    Appsignal.set_namespace("gupshup_webhooks")
    put_in(conn.path_info, new_path)
  end
end
