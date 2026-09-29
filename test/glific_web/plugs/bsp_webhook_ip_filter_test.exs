defmodule GlificWeb.Plugs.BSPWebhookIPFilterTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias GlificWeb.Plugs.BSPWebhookIPFilter

  # RFC 5737 documentation addresses, so no real provider IP is held in the repository.
  @provider_ip "192.0.2.10"
  @attacker_ip "203.0.113.5"

  @allowlist_keys %{
    "gupshup" => :gupshup_webhook_ips,
    "gupshup-enterprise" => :gupshup_enterprise_webhook_ips,
    "maytapi" => :maytapi_webhook_ips
  }

  setup do
    original =
      Map.new(@allowlist_keys, fn {_provider, key} -> {key, Application.get_env(:glific, key)} end)

    on_exit(fn -> Enum.each(original, fn {key, ips} -> put_allowlist(key, ips) end) end)

    :ok
  end

  defp configure(allowlist) do
    Enum.each(@allowlist_keys, fn {provider, key} ->
      put_allowlist(key, Map.get(allowlist, provider))
    end)
  end

  defp put_allowlist(key, nil), do: Application.delete_env(:glific, key)
  defp put_allowlist(key, ips), do: Application.put_env(:glific, key, ips)

  defp build_conn(path, headers) do
    Enum.reduce(headers, conn(:post, path, %{}), fn {header, value}, conn ->
      Plug.Conn.put_req_header(conn, header, value)
    end)
  end

  defp call(path, headers) when is_list(headers),
    do: BSPWebhookIPFilter.call(build_conn(path, headers), BSPWebhookIPFilter.init([]))

  defp call(path, client_ip), do: call(path, [{"x-forwarded-for", client_ip}])

  describe "filtering" do
    setup do
      configure(%{"gupshup" => ["192.0.2.10", "192.0.2.11"], "maytapi" => []})
    end

    test "lets a request from an allowlisted provider IP through" do
      conn = call("/gupshup", @provider_ip)

      refute conn.halted
      assert conn.status == nil
    end

    test "rejects a request from an IP the provider does not publish" do
      conn = call("/gupshup", @attacker_ip)

      assert conn.halted
      assert conn.status == 403
    end

    test "does not filter a provider with an empty allowlist" do
      conn = call("/maytapi", @attacker_ip)

      refute conn.halted
    end

    test "does not filter a provider that is not configured at all" do
      conn = call("/gupshup-enterprise", @attacker_ip)

      refute conn.halted
    end

    test "keeps each provider's allowlist to itself" do
      configure(%{"gupshup" => ["192.0.2.10"], "maytapi" => ["198.51.100.1"]})

      conn = call("/maytapi", @provider_ip)

      assert conn.halted
      assert conn.status == 403
    end

    test "missing config leaves every request untouched" do
      configure(%{})

      conn = call("/gupshup", @attacker_ip)

      refute conn.halted
    end

    test "a request without a path segment is left alone" do
      conn = call("/", @attacker_ip)

      refute conn.halted
    end
  end

  describe "client IP is taken only from x-forwarded-for" do
    setup do
      configure(%{"gupshup" => ["192.0.2.10"]})
    end

    test "takes the last client address the proxy appended" do
      conn = call("/gupshup", "#{@attacker_ip}, #{@provider_ip}")

      refute conn.halted
    end

    test "ignores an allowlisted address supplied in x-real-ip" do
      conn =
        call("/gupshup", [
          {"x-forwarded-for", @attacker_ip},
          {"x-real-ip", @provider_ip}
        ])

      assert conn.halted
      assert conn.status == 403
    end

    test "ignores an allowlisted address supplied in x-client-ip" do
      conn =
        call("/gupshup", [
          {"x-forwarded-for", @attacker_ip},
          {"x-client-ip", @provider_ip}
        ])

      assert conn.halted
      assert conn.status == 403
    end

    test "ignores an allowlisted address supplied in forwarded" do
      conn =
        call("/gupshup", [
          {"x-forwarded-for", @attacker_ip},
          {"forwarded", "for=#{@provider_ip}"}
        ])

      assert conn.halted
      assert conn.status == 403
    end

    test "refuses a request that carries no forwarding header" do
      conn = call("/gupshup", [])

      assert conn.halted
      assert conn.status == 403
    end

    test "does not fall back to the socket peer address" do
      conn =
        %{build_conn("/gupshup", []) | remote_ip: {192, 0, 2, 10}}
        |> BSPWebhookIPFilter.call(BSPWebhookIPFilter.init([]))

      assert conn.halted
      assert conn.status == 403
    end
  end

  describe "matching" do
    test "matches an IP inside a CIDR block" do
      configure(%{"gupshup" => ["198.51.100.0/24"]})

      allowed = call("/gupshup", "198.51.100.7")
      rejected = call("/gupshup", "198.51.101.7")

      refute allowed.halted
      assert rejected.halted
    end

    test "ignores an unparsable entry instead of failing the request" do
      configure(%{"gupshup" => ["not-an-ip", "192.0.2.10"]})

      conn = call("/gupshup", @provider_ip)

      refute conn.halted
    end

    test "an IPv6 caller does not match an IPv4 allowlist" do
      configure(%{"gupshup" => ["192.0.2.10"]})

      conn = call("/gupshup", "2001:db8::1")

      assert conn.halted
    end

    test "matches an IPv6 caller against an IPv6 allowlist" do
      configure(%{"gupshup" => ["2001:db8::/32"]})

      conn = call("/gupshup", "2001:db8::1")

      refute conn.halted
    end
  end

  test "the router runs the filter ahead of the gupshup shunt" do
    configure(%{"gupshup" => ["192.0.2.10"]})

    conn =
      "/gupshup"
      |> build_conn([{"x-forwarded-for", @attacker_ip}])
      |> GlificWeb.Router.call(GlificWeb.Router.init([]))

    assert conn.halted
    assert conn.status == 403
  end
end
