defmodule Glific.PublicUrl do
  @moduledoc """
  Checks that a user-supplied URL points only at public internet addresses, so a server-side
  fetch of it cannot reach loopback, private-network, link-local (cloud metadata) or other
  internal hosts.
  """

  import Bitwise

  @doc "Returns true when `url` is http(s) and every address its host resolves to is public."
  @spec public?(any()) :: boolean()
  def public?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        host
        |> resolve()
        |> all_public?()

      _ ->
        false
    end
  end

  def public?(_url), do: false

  @spec all_public?([:inet.ip_address()]) :: boolean()
  defp all_public?([]), do: false
  defp all_public?(addresses), do: Enum.all?(addresses, &public_address?/1)

  @spec resolve(String.t()) :: [:inet.ip_address()]
  defp resolve(host) do
    host = String.to_charlist(host)

    case :inet.parse_address(host) do
      {:ok, address} -> [address]
      {:error, _} -> Enum.flat_map([:inet, :inet6], &lookup(host, &1))
    end
  end

  @spec lookup(charlist(), :inet | :inet6) :: [:inet.ip_address()]
  defp lookup(host, family) do
    case dns_resolver().getaddrs(host, family) do
      {:ok, addresses} -> addresses
      {:error, _} -> []
    end
  end

  @spec dns_resolver() :: module()
  defp dns_resolver, do: Application.get_env(:glific, :dns_resolver, :inet)

  @spec public_address?(:inet.ip_address()) :: boolean()
  defp public_address?({0, _, _, _}), do: false
  defp public_address?({10, _, _, _}), do: false
  defp public_address?({100, second, _, _}) when second in 64..127, do: false
  defp public_address?({127, _, _, _}), do: false
  defp public_address?({169, 254, _, _}), do: false
  defp public_address?({172, second, _, _}) when second in 16..31, do: false
  defp public_address?({192, 168, _, _}), do: false
  defp public_address?({first, _, _, _}) when first >= 224, do: false
  defp public_address?({_, _, _, _}), do: true

  defp public_address?({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: public_address?({high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF})

  defp public_address?({0, 0, 0, 0, 0, 0, 0, last}) when last in [0, 1], do: false
  defp public_address?({first, _, _, _, _, _, _, _}) when (first &&& 0xFE00) == 0xFC00, do: false
  defp public_address?({first, _, _, _, _, _, _, _}) when (first &&& 0xFFC0) == 0xFE80, do: false
  defp public_address?({first, _, _, _, _, _, _, _}) when (first &&& 0xFF00) == 0xFF00, do: false
  defp public_address?({_, _, _, _, _, _, _, _}), do: true
end
