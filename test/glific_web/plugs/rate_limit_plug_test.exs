defmodule GlificWeb.RateLimitPlugTest do
  use GlificWeb.ConnCase, async: false

  @limit 5

  setup do
    previous = Application.get_env(:glific, :rate_limit_api_global)
    Application.put_env(:glific, :rate_limit_api_global, scale_ms: 60_000, count: @limit)
    on_exit(fn -> Application.put_env(:glific, :rate_limit_api_global, previous) end)
    :ok
  end

  # ExRated buckets are global and outlive a test, so each test needs an address of its own.
  defp unrouted_request(conn, client_ip, path) do
    conn
    |> Plug.Conn.put_req_header("x-forwarded-for", client_ip)
    |> get(path)
  end

  test "lets a caller through until it passes the limit, then answers 429", %{conn: conn} do
    statuses =
      Enum.map(1..(@limit + 3), fn _ ->
        unrouted_request(build_conn(), "198.51.100.10", "/aws.env").status
      end)

    assert Enum.take(statuses, @limit) == List.duplicate(404, @limit)
    assert Enum.drop(statuses, @limit) == [429, 429, 429]
    assert conn
  end

  test "counts one bucket per address rather than per path" do
    Enum.each(1..@limit, fn n ->
      assert unrouted_request(build_conn(), "198.51.100.11", "/unrouted-#{n}.env").status == 404
    end)

    assert unrouted_request(build_conn(), "198.51.100.11", "/a-different-path.env").status == 429
  end

  test "keeps a separate bucket per address" do
    Enum.each(1..(@limit + 1), fn _ ->
      unrouted_request(build_conn(), "198.51.100.12", "/aws.env")
    end)

    assert unrouted_request(build_conn(), "198.51.100.12", "/aws.env").status == 429
    assert unrouted_request(build_conn(), "198.51.100.13", "/aws.env").status == 404
  end

  test "never limits a HEAD request to a route the router only declares for GET", %{
    organization_id: organization_id
  } do
    statuses =
      Enum.map(1..(@limit * 3), fn _ ->
        build_conn()
        |> Plug.Conn.assign(:organization_id, organization_id)
        |> Plug.Conn.put_req_header("x-forwarded-for", "198.51.100.15")
        |> head("/")
        |> Map.fetch!(:status)
      end)

    refute 429 in statuses
  end

  test "never limits a preflight for a method the router does declare on that path" do
    statuses =
      Enum.map(1..(@limit * 3), fn _ ->
        build_conn()
        |> Plug.Conn.put_req_header("x-forwarded-for", "198.51.100.16")
        |> Plug.Conn.put_req_header("origin", "https://example.test")
        |> Plug.Conn.put_req_header("access-control-request-method", "GET")
        |> options("/flow-editor/globals")
        |> Map.fetch!(:status)
      end)

    refute 429 in statuses
  end

  test "limits a preflight flood aimed at a path that matches no route" do
    statuses =
      Enum.map(1..(@limit + 3), fn _ ->
        build_conn()
        |> Plug.Conn.put_req_header("x-forwarded-for", "198.51.100.17")
        |> Plug.Conn.put_req_header("origin", "https://example.test")
        |> Plug.Conn.put_req_header("access-control-request-method", "GET")
        |> options("/aws.env")
        |> Map.fetch!(:status)
      end)

    assert 429 in statuses
  end

  test "limits an OPTIONS flood that carries no preflight header at all" do
    statuses =
      Enum.map(1..(@limit + 3), fn _ ->
        build_conn()
        |> Plug.Conn.put_req_header("x-forwarded-for", "198.51.100.18")
        |> options("/aws.env")
        |> Map.fetch!(:status)
      end)

    assert 429 in statuses
  end

  test "limits HEAD to a path that matches no route, like any other method" do
    statuses =
      Enum.map(1..(@limit + 3), fn _ ->
        build_conn()
        |> Plug.Conn.put_req_header("x-forwarded-for", "198.51.100.19")
        |> head("/aws.env")
        |> Map.fetch!(:status)
      end)

    assert 429 in statuses
  end

  # A route with a glob segment lets the caller choose the path, so keying the bucket on the path
  # made the number of live ExRated buckets unbounded from unauthenticated traffic.
  test "keeps one bucket per address however many distinct paths an unauthenticated caller tries",
       %{organization_id: organization_id} do
    buckets_before = :ets.info(:ex_rated_buckets, :size)

    Enum.each(1..20, fn n ->
      build_conn()
      |> Plug.Conn.assign(:organization_id, organization_id)
      |> Plug.Conn.put_req_header("x-forwarded-for", "198.51.100.20")
      |> get("/flow-editor/revisions/#{n}")
    end)

    assert :ets.info(:ex_rated_buckets, :size) - buckets_before == 1
  end

  test "never limits a path the router matches", %{organization_id: organization_id} do
    statuses =
      Enum.map(1..(@limit * 3), fn _ ->
        build_conn()
        |> Plug.Conn.assign(:organization_id, organization_id)
        |> unrouted_request("198.51.100.14", "/")
        |> Map.fetch!(:status)
      end)

    assert Enum.uniq(statuses) == [200]
  end
end
