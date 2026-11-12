defmodule GlificWeb.Plugs.LogMetadataTest do
  use GlificWeb.ConnCase

  import ExUnit.CaptureLog
  require Logger

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

  test "caps the user agent at 256 bytes", %{conn: conn} do
    conn
    |> put_req_header("user-agent", String.duplicate("a", 5000))
    |> LogMetadata.call([])

    assert byte_size(Logger.metadata()[:user_agent]) == 256
  end

  test "caps by bytes even when the value is one long grapheme", %{conn: conn} do
    conn
    |> put_req_header("user-agent", "a" <> String.duplicate("́", 2000))
    |> LogMetadata.call([])

    user_agent = Logger.metadata()[:user_agent]
    assert byte_size(user_agent) <= 256
    assert String.valid?(user_agent)
  end

  test "escapes control characters", %{conn: conn} do
    conn
    |> put_req_header("user-agent", "evil\e[31mred\x00\x7F")
    |> LogMetadata.call([])

    assert Logger.metadata()[:user_agent] == "evil\\x1B[31mred\\x00\\x7F"
  end

  test "formatted log lines carry no raw control characters", %{conn: conn} do
    level = Logger.level()
    Logger.configure(level: :error)
    on_exit(fn -> Logger.configure(level: level) end)

    conn
    |> put_req_header("user-agent", "evil\e[31mred")
    |> LogMetadata.call([])

    log =
      capture_log([format: "$metadata$message", metadata: [:user_agent]], fn ->
        Logger.error("request")
      end)

    assert log =~ "user_agent=evil\\x1B[31mred request"
    refute log =~ "\e"
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
