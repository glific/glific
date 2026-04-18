defmodule Glific.AppsignalTest do
  use Glific.DataCase, async: true
  import Mock

  # Avoid `alias Glific.Appsignal` — it would shadow the Appsignal dependency used in with_mock.

  defp native_to_milliseconds(native),
    do: System.convert_time_unit(native, :native, :millisecond)

  describe "handle_event/4 repo query telemetry" do
    test "records distribution metrics and query count for :repo when timings are present" do
      measurement = %{
        query_time: 2_000_000,
        idle_time: 1_000_000,
        queue_time: 500_000
      }

      parent = self()

      with_mock Appsignal, [],
        add_distribution_value: fn name, value, tags ->
          send(parent, {:dist, name, value, tags})
          :ok
        end,
        increment_counter: fn name, amount, tags ->
          send(parent, {:cnt, name, amount, tags})
          :ok
        end do
        Glific.Appsignal.handle_event([:glific, :repo, :query], measurement, %{}, nil)
      end

      expected_query_time_ms = native_to_milliseconds(measurement.query_time)
      expected_idle_time_ms = native_to_milliseconds(measurement.idle_time)
      expected_queue_time_ms = native_to_milliseconds(measurement.queue_time)

      assert_receive {:dist, "glific.repo.query_time", ^expected_query_time_ms, %{repo: :repo}}
      assert_receive {:dist, "glific.repo.idle_time", ^expected_idle_time_ms, %{repo: :repo}}
      assert_receive {:dist, "glific.repo.queue_time", ^expected_queue_time_ms, %{repo: :repo}}
      assert_receive {:cnt, "glific.repo.query_count", 1, %{repo: :repo}}
    end

    test "tags metrics with :repo_replica for replica repo events" do
      measurement = %{
        query_time: 2_000_000,
        idle_time: 1_000_000,
        queue_time: 500_000
      }

      parent = self()

      with_mock Appsignal, [],
        add_distribution_value: fn name, value, tags ->
          send(parent, {:dist, name, value, tags})
          :ok
        end,
        increment_counter: fn name, amount, tags ->
          send(parent, {:cnt, name, amount, tags})
          :ok
        end do
        Glific.Appsignal.handle_event([:glific, :repo_replica, :query], measurement, %{}, nil)
      end

      tags = %{repo: :repo_replica}

      assert_receive {:dist, "glific.repo.query_time", _, ^tags}
      assert_receive {:dist, "glific.repo.idle_time", _, ^tags}
      assert_receive {:dist, "glific.repo.queue_time", _, ^tags}
      assert_receive {:cnt, "glific.repo.query_count", 1, ^tags}
    end

    test "does not increment query count when query_time is absent" do
      measurement = %{
        idle_time: 1_000_000,
        queue_time: 500_000
      }

      parent = self()

      with_mock Appsignal, [],
        add_distribution_value: fn name, value, tags ->
          send(parent, {:dist, name, value, tags})
          :ok
        end,
        increment_counter: fn _, _, _ ->
          flunk("increment_counter should not be called when query_time is missing")
        end do
        Glific.Appsignal.handle_event([:glific, :repo, :query], measurement, %{}, nil)
      end

      expected_idle_time_ms = native_to_milliseconds(measurement.idle_time)
      expected_queue_time_ms = native_to_milliseconds(measurement.queue_time)

      assert_receive {:dist, "glific.repo.idle_time", ^expected_idle_time_ms, %{repo: :repo}}
      assert_receive {:dist, "glific.repo.queue_time", ^expected_queue_time_ms, %{repo: :repo}}
      refute_receive {:cnt, _, _, _}
    end

    test "records only metrics for timings that are present" do
      measurement = %{query_time: 3_000_000}
      parent = self()

      with_mock Appsignal, [],
        add_distribution_value: fn name, value, tags ->
          send(parent, {:dist, name, value, tags})
          :ok
        end,
        increment_counter: fn name, amount, tags ->
          send(parent, {:cnt, name, amount, tags})
          :ok
        end do
        Glific.Appsignal.handle_event([:glific, :repo, :query], measurement, %{}, nil)
      end

      expected_query_time_ms = native_to_milliseconds(measurement.query_time)

      assert_receive {:dist, "glific.repo.query_time", ^expected_query_time_ms, %{repo: :repo}}
      assert_receive {:cnt, "glific.repo.query_count", 1, %{repo: :repo}}
      refute_receive {:dist, _, _, _}, 0
    end

    test "does not record metrics when measurement is empty" do
      with_mock Appsignal, [],
        add_distribution_value: fn _, _, _ ->
          flunk("add_distribution_value should not be called")
        end,
        increment_counter: fn _, _, _ ->
          flunk("increment_counter should not be called")
        end do
        assert Glific.Appsignal.handle_event([:glific, :repo, :query], %{}, %{}, nil) == nil
      end
    end

    test "does not record metrics for repo names other than :repo and :repo_replica" do
      with_mock Appsignal, [],
        add_distribution_value: fn _, _, _ ->
          flunk("add_distribution_value should not be called")
        end,
        increment_counter: fn _, _, _ ->
          flunk("increment_counter should not be called")
        end do
        assert Glific.Appsignal.handle_event(
                 [:glific, :other, :query],
                 %{query_time: 1},
                 %{},
                 nil
               ) ==
                 nil
      end
    end

    test "returns nil for unrelated telemetry events" do
      assert Glific.Appsignal.handle_event([:some, :other, :event], %{}, %{}, nil) == nil
    end
  end
end
