defmodule GlificWeb.Plugs.LogMetadataTest do
  use GlificWeb.ConnCase, async: true

  alias GlificWeb.Plugs.LogMetadata

  setup do
    Logger.reset_metadata()
    :ok
  end

  test "puts the user agent into Logger metadata", %{conn: conn} do
    conn
    |> put_req_header("user-agent", "glific-test/1.0")
    |> LogMetadata.call([])

    assert Logger.metadata()[:user_agent] == "glific-test/1.0"
  end

  test "caps the user agent at 256 characters", %{conn: conn} do
    conn
    |> put_req_header("user-agent", String.duplicate("a", 5000))
    |> LogMetadata.call([])

    assert String.length(Logger.metadata()[:user_agent]) == 256
  end

  test "leaves metadata untouched without a user agent", %{conn: conn} do
    LogMetadata.call(conn, [])

    refute Keyword.has_key?(Logger.metadata(), :user_agent)
  end

  test "runs for API requests through the endpoint", %{conn: conn} do
    conn
    |> put_req_header("user-agent", "glific-api-client/2.0")
    |> post("/api/v1/session", %{})

    assert Logger.metadata()[:user_agent] == "glific-api-client/2.0"
  end
end
