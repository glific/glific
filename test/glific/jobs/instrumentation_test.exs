defmodule Glific.Jobs.InstrumentationTest do
  use Glific.DataCase, async: true

  import Mock

  alias Glific.Jobs.Instrumentation

  describe "track/3" do
    test "returns the wrapped value unchanged for each outcome shape" do
      assert Instrumentation.track("job", 1, fn -> :ok end) == :ok
      assert Instrumentation.track("job", 1, fn -> {:ok, %{id: 5}} end) == {:ok, %{id: 5}}
      assert Instrumentation.track("job", 1, fn -> {:error, "boom"} end) == {:error, "boom"}
      assert Instrumentation.track("job", 1, fn -> {:discard, "gone"} end) == {:discard, "gone"}
    end

    test "runs the wrapped function exactly once" do
      counter = :counters.new(1, [])
      Instrumentation.track("job", 1, fn -> :counters.add(counter, 1, 1) end)
      assert :counters.get(counter, 1) == 1
    end

    test "re-raises an exception from the wrapped function" do
      assert_raise RuntimeError, "kaboom", fn ->
        Instrumentation.track("job", 1, fn -> raise "kaboom" end)
      end
    end

    test "tolerates a nil organization_id" do
      assert Instrumentation.track("job", nil, fn -> :ok end) == :ok
    end
  end

  describe "heartbeat/1" do
    test "checks in under the minute worker identifier by default" do
      parent = self()

      with_mock Appsignal.CheckIn,
        heartbeat: fn identifier ->
          send(parent, {:heartbeat, identifier})
          :ok
        end do
        assert Instrumentation.heartbeat() == :ok
      end

      assert_received {:heartbeat, "glific_minute_worker"}
    end

    test "checks in under an explicit identifier" do
      parent = self()

      with_mock Appsignal.CheckIn,
        heartbeat: fn identifier ->
          send(parent, {:heartbeat, identifier})
          :ok
        end do
        assert Instrumentation.heartbeat("some_other_cron") == :ok
      end

      assert_received {:heartbeat, "some_other_cron"}
    end

    test "swallows a failure to check in, so it cannot fail the job it reports on" do
      with_mock Appsignal.CheckIn, heartbeat: fn _identifier -> raise "appsignal down" end do
        assert Instrumentation.heartbeat() == :ok
      end
    end
  end
end
