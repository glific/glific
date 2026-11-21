defmodule GlificWeb.Plugs.HealthCheckTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias GlificWeb.Plugs.HealthCheck

  defp request(method, path), do: method |> conn(path) |> HealthCheck.call([])

  test "answers the health check on /health and /" do
    for path <- ["/health", "/"] do
      conn = request(:get, path)
      assert {conn.status, conn.resp_body} == {200, "ok"}
    end
  end

  test "answers a HEAD health check" do
    assert request(:head, "/health").status == 200
  end

  test "refuses every other path and method" do
    for {method, path} <- [{:get, "/api"}, {:post, "/health"}, {:get, "/socket/websocket"}] do
      assert request(method, path).status == 404
    end
  end
end
