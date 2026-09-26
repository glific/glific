defmodule GlificWeb.Plugs.IPBlocklist do
  @moduledoc """
  Drops every request from a blocked source address with a 404.

  This sits high in `GlificWeb.Endpoint`, directly after `GlificWeb.Plugs.LogMetadata` and before
  the body parsers and `GlificWeb.SubdomainPlug`, so a blocked caller costs us no body buffering
  and no organization lookup — but is still logged with its IP and status like any other request.

  The list comes from the environment as comma separated entries, so adding a scanner is a
  `gigalixir config:set` and a restart rather than a deploy:

      gigalixir config:set BLOCKED_IPS="203.0.113.5,2001:db8::1,198.51.100.0/24"

  IPv4, IPv6 and CIDR blocks are all accepted; `config/runtime.exs` validates each entry and
  refuses to boot on a malformed one. An unset or empty list disables the plug entirely.

  404 rather than 403 is deliberate: it is the same answer an unknown path already gets, so a
  scanner learns nothing about whether it has been singled out.

  The address is `conn.remote_ip`, which `RemoteIp` has already resolved from the one header our
  proxy controls. Blocking on a caller-settable header would let anyone put a blocked address on
  someone else's request.
  """

  alias Plug.Conn

  @behaviour Plug

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc false
  @spec call(Conn.t(), Plug.opts()) :: Conn.t()
  def call(conn, _opts) do
    case Application.get_env(:glific, :blocked_ips, []) do
      [] -> conn
      blocklist -> block(conn, blocklist)
    end
  end

  @spec block(Conn.t(), [String.t()]) :: Conn.t()
  defp block(conn, blocklist) do
    if blocked?(conn.remote_ip, blocklist) do
      conn
      |> Conn.send_resp(404, "")
      |> Conn.halt()
    else
      conn
    end
  end

  @spec blocked?(:inet.ip_address(), [String.t()]) :: boolean()
  defp blocked?(remote_ip, blocklist) do
    Enum.any?(blocklist, fn entry ->
      case parse_cidr(entry) do
        {:ok, cidr} -> InetCidr.contains?(cidr, remote_ip)
        :error -> false
      end
    end)
  end

  @spec parse_cidr(String.t()) :: {:ok, tuple()} | :error
  defp parse_cidr(entry) do
    case InetCidr.parse_cidr(with_prefix_length(entry)) do
      {:ok, cidr} -> {:ok, cidr}
      {:error, _reason} -> :error
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
end
