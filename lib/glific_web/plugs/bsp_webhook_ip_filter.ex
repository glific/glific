defmodule GlificWeb.Plugs.BSPWebhookIPFilter do
  @moduledoc """
  Restricts the BSP webhook endpoints to the source IPs published by each provider.

  These endpoints are unauthenticated: the organization is resolved from the request
  host and the shunt then runs the request as that organization's root user. Filtering
  on the provider's published callback IPs is what stops an arbitrary caller from
  posting a forged inbound message on behalf of any organization.

  The provider is the first path segment (`/gupshup`, `/gupshup-enterprise`,
  `/maytapi`) and is looked up in the `:bsp_webhook_ip_allowlist` config:

      config :glific, :bsp_webhook_ip_allowlist, %{"gupshup" => ["192.0.2.10", "198.51.100.0/24"]}

  Entries are IPv4/IPv6 addresses or CIDR blocks. A caller outside its provider's list is
  logged and answered with 403. That log line is the only warning that a provider has
  started calling from an address we do not know about, so it is worth alerting on.

  A provider whose list is empty is not filtered at all. That is what keeps a route
  working before its IPs are known, and what leaves dev and test unfiltered, since
  `config/runtime.exs` only populates the lists in `:prod`.

  The lists come per provider from the environment (`GUPSHUP_WEBHOOK_IPS` and friends)
  and are deliberately not held in this repository, so a provider adding an IP is a
  `gigalixir config:set` and a restart rather than a deploy. Because an empty list means
  no filtering, `runtime.exs` refuses to boot `:prod` when `GUPSHUP_WEBHOOK_IPS` is
  missing rather than let the busiest webhook come up unguarded.

  The caller is taken from `x-forwarded-for` alone, rather than from `conn.remote_ip`.
  `GlificWeb.Endpoint` runs `RemoteIp` with its defaults, which also trust `forwarded`,
  `x-client-ip` and `x-real-ip`; our proxy only rewrites `x-forwarded-for`, so a caller
  that sends one of the other three can put an allowlisted address last in the chain and
  have it win. Deciding here from the one header the proxy controls keeps that out of a
  security decision, and leaves `conn.remote_ip` untouched for rate limiting and logging.

  A request with no usable `x-forwarded-for` cannot be attributed to anyone and is
  refused, with a distinct log line — in production every request arrives through the
  proxy, so that means the proxy is not sending the header we expect.
  """

  require Logger

  alias Plug.Conn

  @behaviour Plug

  @forwarding_headers ~w[x-forwarded-for]

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc false
  @spec call(Conn.t(), Plug.opts()) :: Conn.t()
  def call(%Conn{path_info: [provider | _]} = conn, _opts) do
    case allowlist(provider) do
      [] -> conn
      allowlist -> filter(conn, provider, allowlist)
    end
  end

  def call(conn, _opts), do: conn

  @spec filter(Conn.t(), String.t(), [String.t()]) :: Conn.t()
  defp filter(conn, provider, allowlist) do
    case client_ip(conn) do
      nil ->
        reject(conn, "Request to the #{provider} webhook carried no usable x-forwarded-for")

      client_ip ->
        if allowed?(client_ip, allowlist),
          do: conn,
          else: reject(conn, "Unlisted IP #{format_ip(client_ip)} called the #{provider} webhook")
    end
  end

  @spec reject(Conn.t(), String.t()) :: Conn.t()
  defp reject(conn, message) do
    Logger.warning(message)

    conn
    |> Conn.send_resp(403, "")
    |> Conn.halt()
  end

  @spec client_ip(Conn.t()) :: :inet.ip_address() | nil
  defp client_ip(conn), do: RemoteIp.from(conn.req_headers, headers: @forwarding_headers)

  @spec format_ip(:inet.ip_address()) :: String.t()
  defp format_ip(client_ip), do: client_ip |> :inet_parse.ntoa() |> to_string()

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

  @spec allowlist(String.t()) :: [String.t()]
  defp allowlist(provider) do
    case Application.get_env(:glific, :bsp_webhook_ip_allowlist) do
      allowlist when is_map(allowlist) -> Map.get(allowlist, provider, [])
      _unconfigured -> []
    end
  end
end
