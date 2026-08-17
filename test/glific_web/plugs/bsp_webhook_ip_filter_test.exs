defmodule GlificWeb.Plugs.BSPWebhookIPFilterTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias GlificWeb.Plugs.BSPWebhookIPFilter

  @gupshup_ip {34, 202, 224, 208}
  @attacker_ip {203, 0, 113, 5}

  setup do
    original = Application.get_env(:glific, :bsp_webhook_ip_allowlist)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:glific, :bsp_webhook_ip_allowlist)
        allowlist -> Application.put_env(:glific, :bsp_webhook_ip_allowlist, allowlist)
      end
    end)

    :ok
  end

  defp configure(allowlist),
    do: Application.put_env(:glific, :bsp_webhook_ip_allowlist, allowlist)

  defp call(path, remote_ip) do
    conn = %{conn(:post, path, %{}) | remote_ip: remote_ip}

    BSPWebhookIPFilter.call(conn, BSPWebhookIPFilter.init([]))
  end

  describe "filtering" do
    setup do
      configure(%{"gupshup" => ["34.202.224.208", "3.6.228.131"], "maytapi" => []})
    end

    test "lets a request from an allowlisted provider IP through" do
      conn = call("/gupshup", @gupshup_ip)

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
      configure(%{"gupshup" => ["34.202.224.208"], "maytapi" => ["1.2.3.4"]})

      conn = call("/maytapi", @gupshup_ip)

      assert conn.halted
      assert conn.status == 403
    end

    test "missing config leaves every request untouched" do
      Application.delete_env(:glific, :bsp_webhook_ip_allowlist)

      conn = call("/gupshup", @attacker_ip)

      refute conn.halted
    end

    test "a request without a path segment is left alone" do
      conn = call("/", @attacker_ip)

      refute conn.halted
    end
  end

  describe "matching" do
    test "matches an IP inside a CIDR block" do
      configure(%{"gupshup" => ["3.6.0.0/16"]})

      allowed = call("/gupshup", {3, 6, 228, 131})
      rejected = call("/gupshup", {3, 7, 115, 196})

      refute allowed.halted
      assert rejected.halted
    end

    test "ignores an unparsable entry instead of failing the request" do
      configure(%{"gupshup" => ["not-an-ip", "34.202.224.208"]})

      conn = call("/gupshup", @gupshup_ip)

      refute conn.halted
    end

    test "an IPv6 caller does not match an IPv4 allowlist" do
      configure(%{"gupshup" => ["34.202.224.208"]})

      conn = call("/gupshup", {0, 0, 0, 0, 0, 0, 0, 1})

      assert conn.halted
    end
  end

  test "the router runs the filter ahead of the gupshup shunt" do
    configure(%{"gupshup" => ["34.202.224.208"]})

    conn =
      %{conn(:post, "/gupshup", %{}) | remote_ip: @attacker_ip}
      |> GlificWeb.Router.call(GlificWeb.Router.init([]))

    assert conn.halted
    assert conn.status == 403
  end
end
