defmodule Glific.RateLimitTest do
  use Glific.DataCase, async: false

  import ExUnit.CaptureLog

  alias Glific.RateLimit

  @limit :a_test_limit

  # config/test.exs runs the logger at :emergency, so without raising it every assertion below
  # would hold whether or not a breach was reported.
  setup do
    level = Logger.level()
    Logger.configure(level: :warning)
    on_exit(fn -> Logger.configure(level: level) end)
    :ok
  end

  defp unique_key, do: "rate-limit-test:#{System.unique_integer([:positive])}"

  defp with_limit(count, fun) do
    Application.put_env(:glific, @limit, scale_ms: 60_000, count: count)

    try do
      fun.()
    after
      Application.delete_env(:glific, @limit)
    end
  end

  test "allows requests up to the configured count and reports nothing" do
    with_limit(3, fn ->
      key = unique_key()

      log =
        capture_log(fn ->
          Enum.each(1..3, fn _ -> assert :ok == RateLimit.check(@limit, key) end)
        end)

      refute log =~ "Rate limit exceeded"
    end)
  end

  test "reports a breach as a warning naming the limit" do
    with_limit(2, fn ->
      key = unique_key()

      log =
        capture_log(fn ->
          Enum.each(1..2, fn _ -> RateLimit.check(@limit, key) end)
          assert {:error, :rate_limited} == RateLimit.check(@limit, key)
        end)

      assert log =~ "[warning]"
      assert log =~ "Rate limit exceeded: a_test_limit"
    end)
  end

  # Keys carry addresses, phone numbers and contact ids.
  test "never reports the bucket key" do
    with_limit(0, fn ->
      key = unique_key()

      log = capture_log(fn -> RateLimit.check(@limit, key) end)

      assert log =~ "Rate limit exceeded"
      refute log =~ key
    end)
  end

  # A limit that quietly stops limiting is worse than one that fails loudly.
  test "raises rather than guessing when a limit is not configured" do
    assert_raise ArgumentError, fn ->
      RateLimit.check(:a_limit_nobody_configured, unique_key())
    end
  end

  test "raises when a configured limit is missing its count" do
    Application.put_env(:glific, @limit, scale_ms: 60_000)
    on_exit(fn -> Application.delete_env(:glific, @limit) end)

    assert_raise KeyError, fn -> RateLimit.check(@limit, unique_key()) end
  end
end
