defmodule Glific.RateLimitTest do
  use Glific.DataCase, async: false

  alias Glific.RateLimit

  @event [:glific, :rate_limit, :exceeded]
  @limit :a_test_limit

  setup do
    handler = "rate-limit-test-#{System.unique_integer([:positive])}"
    test_process = self()

    :telemetry.attach(
      handler,
      @event,
      fn event, measurements, metadata, _config ->
        send(test_process, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
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

      Enum.each(1..3, fn _ -> assert :ok == RateLimit.check(@limit, key) end)

      refute_received {:telemetry, @event, _measurements, _metadata}
    end)
  end

  test "reports a breach as telemetry tagged with the limit name" do
    with_limit(2, fn ->
      key = unique_key()

      Enum.each(1..2, fn _ -> RateLimit.check(@limit, key) end)

      assert {:error, :rate_limited} == RateLimit.check(@limit, key)

      assert_received {:telemetry, @event, measurements, metadata}
      assert measurements.count == 1
      assert measurements.limit == 2
      assert metadata.limit == "a_test_limit"
    end)
  end

  # Keys carry addresses, phone numbers and contact ids.
  test "never reports the bucket key" do
    with_limit(0, fn ->
      key = unique_key()
      RateLimit.check(@limit, key)

      assert_received {:telemetry, @event, _measurements, metadata}
      refute metadata |> Map.values() |> Enum.any?(&(&1 == key))
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
