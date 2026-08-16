defmodule GlificWeb.Plugs.BSPWebhookIPFilter do
  @moduledoc """
  Restricts the BSP webhook endpoints to the source IPs published by each provider.

  These endpoints are unauthenticated: the organization is resolved from the request
  host and the shunt then runs the request as that organization's root user. Filtering
  on the provider's published callback IPs is what stops an arbitrary caller from
  posting a forged inbound message on behalf of any organization.

  The provider is the first path segment (`/gupshup`, `/gupshup-enterprise`,
  `/maytapi`) and is looked up in the `:bsp_webhook_ip_filter` config:

      config :glific, :bsp_webhook_ip_filter,
        mode: :enforce,
        allowlist: %{"gupshup" => ["34.202.224.208", "3.6.0.0/16"]}

  Entries are IPv4/IPv6 addresses or CIDR blocks. Modes:

    * `:enforce` - requests from outside the allowlist are logged and answered with 403
    * `:log` - requests from outside the allowlist are logged and let through, to
      validate a list against real traffic before turning enforcement on
    * `:disabled` - no filtering at all

  A provider whose allowlist is empty is never filtered, whatever the mode, so a route
  is not silently broken before its IP list is known.

  The check uses `conn.remote_ip`, which is derived from `X-Forwarded-For` by the
  `RemoteIp` plug in `GlificWeb.Endpoint`; that plug has to stay ahead of the router
  for this filter to see the real client IP.
  """

  require Logger

  alias GlificWeb.Tenants
  alias Plug.Conn

  @behaviour Plug

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc false
  @spec call(Conn.t(), Plug.opts()) :: Conn.t()
  def call(%Conn{path_info: [provider | _]} = conn, _opts) do
    case {mode(), allowlist(provider)} do
      {:disabled, _allowlist} -> conn
      {_mode, []} -> conn
      {mode, allowlist} -> filter(conn, provider, mode, allowlist)
    end
  end

  def call(conn, _opts), do: conn

  @spec filter(Conn.t(), String.t(), atom(), [String.t()]) :: Conn.t()
  defp filter(conn, provider, mode, allowlist) do
    if allowed?(conn.remote_ip, allowlist) do
      conn
    else
      Logger.warning(
        "Unlisted IP #{Tenants.remote_ip(conn)} called the #{provider} webhook, filter mode: #{mode}"
      )

      if mode == :enforce,
        do: conn |> Conn.send_resp(403, "") |> Conn.halt(),
        else: conn
    end
  end

  @spec allowed?(:inet.ip_address(), [String.t()]) :: boolean()
  defp allowed?(remote_ip, allowlist) do
    Enum.any?(allowlist, fn entry ->
      case parse_cidr(entry) do
        {:ok, cidr} -> InetCidr.contains?(cidr, remote_ip)
        :error -> false
      end
    end)
  end

  @spec parse_cidr(String.t()) :: {:ok, tuple()} | :error
  defp parse_cidr(entry) do
    case InetCidr.parse_cidr(with_prefix_length(entry)) do
      {:ok, cidr} ->
        {:ok, cidr}

      {:error, _reason} ->
        Logger.warning("Ignoring invalid BSP webhook allowlist entry: #{entry}")
        :error
    end
  end

  @spec with_prefix_length(String.t()) :: String.t()
  defp with_prefix_length(entry) do
    cond do
      String.contains?(entry, "/") -> entry
      String.contains?(entry, ":") -> entry <> "/128"
      true -> entry <> "/32"
    end
  end

  @spec mode() :: atom()
  defp mode, do: Keyword.get(config(), :mode, :disabled)

  @spec allowlist(String.t()) :: [String.t()]
  defp allowlist(provider) do
    config()
    |> Keyword.get(:allowlist, %{})
    |> Map.get(provider, [])
  end

  @spec config() :: keyword()
  defp config, do: Application.get_env(:glific, :bsp_webhook_ip_filter, [])
end
