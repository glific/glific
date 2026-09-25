defmodule GlificWeb.Plugs.IPBlocklistTest do
  use GlificWeb.ConnCase, async: false

  # RFC 5737 / RFC 3849 documentation addresses, standing in for scanners.
  @blocked_v4 "203.0.113.5"
  @blocked_v6 "2001:db8::1"
  @blocked_block "198.51.100.0/24"
  @allowed_v4 "192.0.2.7"

  defp block(blocklist) do
    Application.put_env(:glific, :blocked_ips, blocklist)
    on_exit(fn -> Application.put_env(:glific, :blocked_ips, []) end)
  end

  defp request(conn, client_ip, path \\ "/aws.env") do
    conn
    |> Plug.Conn.put_req_header("x-forwarded-for", client_ip)
    |> get(path)
  end

  test "drops a blocked IPv4 address with a 404", %{conn: conn} do
    block([@blocked_v4])

    assert request(conn, @blocked_v4).status == 404
  end

  test "drops a blocked IPv6 address with a 404", %{conn: conn} do
    block([@blocked_v6])

    assert request(conn, @blocked_v6).status == 404
  end

  test "drops an address inside a blocked CIDR block", %{conn: conn} do
    block([@blocked_block])

    assert request(conn, "198.51.100.42").status == 404
  end

  test "drops a blocked caller on a route that would otherwise succeed", %{conn: conn} do
    block([@blocked_v4])

    conn = request(conn, @blocked_v4, "/")

    assert conn.status == 404
    assert conn.resp_body == ""
    assert conn.halted
  end

  test "lets an address outside the list through to its normal response", %{conn: conn} do
    block([@blocked_v4, @blocked_block])

    assert request(conn, @allowed_v4, "/").status == 200
  end

  test "is disabled when the list is empty", %{conn: conn} do
    block([])

    assert request(conn, @blocked_v4, "/").status == 200
  end

  test "ignores a malformed entry rather than failing open or crashing", %{conn: conn} do
    block(["not-an-ip", @blocked_v4])

    assert request(conn, @allowed_v4, "/").status == 200
    assert request(conn, @blocked_v4).status == 404
  end

  test "cannot be triggered for someone else via a caller-settable header", %{conn: conn} do
    block([@blocked_v4])

    conn =
      conn
      |> Plug.Conn.put_req_header("x-real-ip", @blocked_v4)
      |> get("/")

    assert conn.status == 200
  end
end
