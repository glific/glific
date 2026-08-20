defmodule Glific.Triggers.InstrumentationTest do
  @moduledoc false
  # Not async: the threshold tests move application env, which is global.
  use Glific.DataCase, async: false

  import Mock

  alias Glific.Triggers.{Instrumentation, Trigger}

  # Appsignal's metric calls are no-op NIF calls in test, so the assertions capture the
  # arguments instead — the metric names and tag values are the contract an alert is built on.
  defp capture_metrics(fun) do
    parent = self()

    with_mock Appsignal,
              [:passthrough],
              add_distribution_value: fn name, value, tags ->
                send(parent, {:metric, name, value, tags})
                :ok
              end,
              increment_counter: fn name, value, tags ->
                send(parent, {:metric, name, value, tags})
                :ok
              end do
      fun.()
    end

    collect([])
  end

  defp collect(acc) do
    receive do
      {:metric, name, value, tags} -> collect([{name, value, tags} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp fetch(metrics, name) do
    Enum.find(metrics, fn {metric_name, _value, _tags} -> metric_name == name end)
  end

  defp trigger(attrs \\ %{}) do
    defaults = %{
      id: 42,
      organization_id: 1,
      frequency: ["daily"],
      next_trigger_at: DateTime.utc_now()
    }

    struct!(Trigger, Map.merge(defaults, attrs))
  end

  defp scheduled_seconds_ago(seconds),
    do: trigger(%{next_trigger_at: DateTime.add(DateTime.utc_now(), -seconds, :second)})

  defp put_threshold(key, value) do
    previous = Application.get_env(:glific, key)
    Application.put_env(:glific, key, value)
    on_exit(fn -> restore(key, previous) end)
  end

  defp restore(key, nil), do: Application.delete_env(:glific, key)
  defp restore(key, previous), do: Application.put_env(:glific, key, previous)

  describe "track_execution/2" do
    test "returns the wrapped value unchanged and runs the function exactly once" do
      counter = :counters.new(1, [])

      result =
        Instrumentation.track_execution(trigger(), fn ->
          :counters.add(counter, 1, 1)
          {:ok, :started}
        end)

      assert result == {:ok, :started}
      assert :counters.get(counter, 1) == 1
    end

    test "records the drift between scheduled_at and started_at" do
      metrics =
        capture_metrics(fn ->
          Instrumentation.track_execution(scheduled_seconds_ago(90), fn -> :ok end)
        end)

      assert {"trigger_start_drift_seconds", drift, tags} =
               fetch(metrics, "trigger_start_drift_seconds")

      assert_in_delta drift, 90, 2
      assert tags.organization_id == "1"
      assert tags.frequency == "daily"
    end

    test "clamps an early start to zero rather than reporting negative drift" do
      # execute_triggers/2 looks a minute ahead, so a trigger can legitimately start early.
      early = trigger(%{next_trigger_at: DateTime.add(DateTime.utc_now(), 45, :second)})

      metrics = capture_metrics(fn -> Instrumentation.track_execution(early, fn -> :ok end) end)

      assert {"trigger_start_drift_seconds", 0, _tags} =
               fetch(metrics, "trigger_start_drift_seconds")
    end

    test "skips the drift metric when the trigger has no scheduled time" do
      metrics =
        capture_metrics(fn ->
          Instrumentation.track_execution(trigger(%{next_trigger_at: nil}), fn -> :ok end)
        end)

      refute fetch(metrics, "trigger_start_drift_seconds")
      assert fetch(metrics, "trigger_execution_duration_milliseconds")
    end

    test "flags drift past the configured threshold" do
      put_threshold(:trigger_start_drift_seconds, 60)

      metrics =
        capture_metrics(fn ->
          Instrumentation.track_execution(scheduled_seconds_ago(600), fn -> :ok end)
        end)

      assert {"trigger_start_drift_exceeded", 1, tags} =
               fetch(metrics, "trigger_start_drift_exceeded")

      assert tags.organization_id == "1"
      assert tags.frequency == "daily"
    end

    test "does not flag drift inside the configured threshold" do
      put_threshold(:trigger_start_drift_seconds, 300)

      metrics =
        capture_metrics(fn ->
          Instrumentation.track_execution(scheduled_seconds_ago(10), fn -> :ok end)
        end)

      refute fetch(metrics, "trigger_start_drift_exceeded")
    end

    test "records elapsed milliseconds tagged success" do
      metrics =
        capture_metrics(fn ->
          Instrumentation.track_execution(trigger(), fn -> Process.sleep(15) end)
        end)

      assert {"trigger_execution_duration_milliseconds", elapsed, tags} =
               fetch(metrics, "trigger_execution_duration_milliseconds")

      assert elapsed >= 15
      assert tags.status == "success"
      assert tags.organization_id == "1"
    end

    test "flags an execution past the configured duration budget" do
      put_threshold(:trigger_duration_seconds, 0)

      metrics =
        capture_metrics(fn ->
          Instrumentation.track_execution(trigger(), fn -> Process.sleep(5) end)
        end)

      assert {"trigger_execution_slow", 1, _tags} = fetch(metrics, "trigger_execution_slow")
    end

    test "records elapsed time tagged exception and re-raises" do
      metrics =
        capture_metrics(fn ->
          assert_raise RuntimeError, "kaboom", fn ->
            Instrumentation.track_execution(trigger(), fn -> raise "kaboom" end)
          end
        end)

      assert {"trigger_execution_duration_milliseconds", _elapsed, tags} =
               fetch(metrics, "trigger_execution_duration_milliseconds")

      assert tags.status == "exception"
    end

    test "tolerates a nil organization_id" do
      metrics =
        capture_metrics(fn ->
          Instrumentation.track_execution(trigger(%{organization_id: nil}), fn -> :ok end)
        end)

      assert {_name, _value, tags} = fetch(metrics, "trigger_execution_duration_milliseconds")
      assert tags.organization_id == "unknown"
    end

    test "tags an unrecognised frequency as unknown" do
      metrics =
        capture_metrics(fn ->
          Instrumentation.track_execution(
            scheduled_seconds_ago(30) |> Map.put(:frequency, []),
            fn -> :ok end
          )
        end)

      assert {_name, _value, tags} = fetch(metrics, "trigger_start_drift_seconds")
      assert tags.frequency == "unknown"
    end
  end
end
