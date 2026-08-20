defmodule Glific.AppsignalTest do
  use Glific.DataCase

  import Mock

  alias Glific.{Appsignal, Fixtures, Repo}

  defp call_handle_event(args) do
    meta = %{queue: "default", worker: "TestWorker", args: args}
    measurement = %{queue_time: 1_500_000, duration: 2_000_000}
    Appsignal.handle_event([:oban, :job, :stop], measurement, meta, nil)
  end

  describe "handle_event [:oban, :job, :stop] with organization_id extraction" do
    test "handles top-level organization_id" do
      result = call_handle_event(%{"organization_id" => 1})
      assert result in [:ok, nil]
    end

    test "handles nested message organization_id" do
      result = call_handle_event(%{"message" => %{"organization_id" => 2}})
      assert result in [:ok, nil]
    end

    test "handles nested media organization_id" do
      result = call_handle_event(%{"media" => %{"organization_id" => 3}})
      assert result in [:ok, nil]
    end

    test "handles nil organization_id gracefully" do
      result = call_handle_event(%{"organization_id" => nil})
      assert result in [:ok, nil]
    end

    test "handles empty args gracefully" do
      result = call_handle_event(%{})
      assert result in [:ok, nil]
    end

    test "handles args with no organization_id at any level" do
      result = call_handle_event(%{"foo" => "bar"})
      assert result in [:ok, nil]
    end
  end

  describe "send_oban_queue_size/0" do
    test "executes without error" do
      assert Appsignal.send_oban_queue_size() == :ok
    end
  end

  describe "send_message_broadcast_size/0" do
    # Appsignal's metric calls are no-op NIF calls in test, so the assertions capture the
    # arguments instead — the metric names and tag values are the contract an alert is built on.
    defp capture_metrics(fun) do
      parent = self()

      with_mock Elixir.Appsignal,
                [:passthrough],
                set_gauge: fn name, value, tags ->
                  send(parent, {:metric, name, value, tags})
                  :ok
                end,
                increment_counter: fn name, value, tags ->
                  send(parent, {:metric, name, value, tags})
                  :ok
                end do
        fun.()
      end

      collect_metrics([])
    end

    defp collect_metrics(acc) do
      receive do
        {:metric, name, value, tags} -> collect_metrics([{name, value, tags} | acc])
      after
        0 -> Enum.reverse(acc)
      end
    end

    defp metric(metrics, name, organization_id) do
      Enum.find(metrics, fn {metric_name, _value, tags} ->
        metric_name == name and tags.organization_id == to_string(organization_id)
      end)
    end

    defp completed_now, do: Elixir.DateTime.utc_now() |> Elixir.DateTime.truncate(:second)

    defp with_threshold(threshold) do
      previous = Application.get_env(:glific, :message_broadcast_pending_threshold)
      Application.put_env(:glific, :message_broadcast_pending_threshold, threshold)

      on_exit(fn ->
        if is_nil(previous),
          do: Application.delete_env(:glific, :message_broadcast_pending_threshold),
          else: Application.put_env(:glific, :message_broadcast_pending_threshold, previous)
      end)
    end

    test "emits a total and a pending gauge per organization",
         %{organization_id: organization_id} = attrs do
      Fixtures.message_broadcast_fixture(attrs)
      Fixtures.message_broadcast_fixture(attrs)
      Fixtures.message_broadcast_fixture(Map.put(attrs, :completed_at, completed_now()))

      metrics = capture_metrics(fn -> assert Appsignal.send_message_broadcast_size() == :ok end)

      assert {_name, 3, _tags} = metric(metrics, "message_broadcast_row_count", organization_id)

      assert {_name, 2, _tags} =
               metric(metrics, "message_broadcast_pending_count", organization_id)
    end

    test "counts only incomplete broadcasts as pending",
         %{organization_id: organization_id} = attrs do
      completed = Map.put(attrs, :completed_at, completed_now())
      Fixtures.message_broadcast_fixture(completed)
      Fixtures.message_broadcast_fixture(completed)

      metrics = capture_metrics(fn -> Appsignal.send_message_broadcast_size() end)

      assert {_name, 2, _tags} = metric(metrics, "message_broadcast_row_count", organization_id)

      assert {_name, 0, _tags} =
               metric(metrics, "message_broadcast_pending_count", organization_id)
    end

    test "flags a backlog past the configured threshold",
         %{organization_id: organization_id} = attrs do
      with_threshold(1)

      Fixtures.message_broadcast_fixture(attrs)
      Fixtures.message_broadcast_fixture(attrs)

      metrics = capture_metrics(fn -> Appsignal.send_message_broadcast_size() end)

      assert {_name, 1, _tags} =
               metric(metrics, "message_broadcast_backlog_exceeded", organization_id)
    end

    test "does not flag a backlog inside the configured threshold",
         %{organization_id: organization_id} = attrs do
      with_threshold(5)

      Fixtures.message_broadcast_fixture(attrs)

      metrics = capture_metrics(fn -> Appsignal.send_message_broadcast_size() end)

      refute metric(metrics, "message_broadcast_backlog_exceeded", organization_id)
    end

    test "reports each organization separately, so one tenant's backlog is not masked",
         %{organization_id: organization_id} = attrs do
      other = Fixtures.organization_fixture(%{shortcode: "broadcast_gauge_org"})

      # organization_fixture/1 leaves the process scoped to the organization it just created
      Fixtures.message_broadcast_fixture(%{organization_id: other.id})

      Fixtures.message_broadcast_fixture(%{
        organization_id: other.id,
        completed_at: completed_now()
      })

      Repo.put_organization_id(organization_id)
      Fixtures.message_broadcast_fixture(attrs)

      metrics = capture_metrics(fn -> Appsignal.send_message_broadcast_size() end)

      assert {_name, 1, _tags} =
               metric(metrics, "message_broadcast_pending_count", organization_id)

      assert {_name, 2, _tags} = metric(metrics, "message_broadcast_row_count", other.id)
      assert {_name, 1, _tags} = metric(metrics, "message_broadcast_pending_count", other.id)
    end

    test "emits no broadcast metric when no organization has any broadcast" do
      metrics = capture_metrics(fn -> assert Appsignal.send_message_broadcast_size() == :ok end)

      refute Enum.any?(metrics, fn {name, _value, _tags} ->
               String.starts_with?(name, "message_broadcast")
             end)
    end
  end

  describe "handle_event [:glific, :repo, :query] DBConnection error tracking" do
    defp query_event(result) do
      Appsignal.handle_event(
        [:glific, :repo, :query],
        %{queue_time: 1_000_000},
        %{result: result, query: "SELECT 1"},
        nil
      )
    end

    test "tracks DBConnection.ConnectionError atom reasons in result" do
      error = %DBConnection.ConnectionError{
        reason: :queue_timeout,
        message: "queue timeout after 2999ms"
      }

      with_mock Elixir.Appsignal,
                [:passthrough],
                add_distribution_value: fn _, _, _ -> :ok end,
                increment_counter: fn _, _, _ -> :ok end do
        assert query_event({:error, error}) == :ok

        assert called(
                 Elixir.Appsignal.increment_counter("glific.repo.db_connection_error", 1, %{
                   repo: :repo,
                   reason: "queue_timeout"
                 })
               )
      end
    end

    test "tracks DBConnection.ConnectionError string reasons in result" do
      error = %DBConnection.ConnectionError{reason: "custom_error", message: "custom error"}

      with_mock Elixir.Appsignal,
                [:passthrough],
                add_distribution_value: fn _, _, _ -> :ok end,
                increment_counter: fn _, _, _ -> :ok end do
        assert query_event({:error, error}) == :ok

        assert called(
                 Elixir.Appsignal.increment_counter("glific.repo.db_connection_error", 1, %{
                   repo: :repo,
                   reason: "custom_error"
                 })
               )
      end
    end

    test "tracks DBConnection.ConnectionError nil reasons in result" do
      error = %DBConnection.ConnectionError{reason: nil, message: "queue timeout after 2999ms"}

      with_mock Elixir.Appsignal,
                [:passthrough],
                add_distribution_value: fn _, _, _ -> :ok end,
                increment_counter: fn _, _, _ -> :ok end do
        assert query_event({:error, error}) == :ok

        assert called(
                 Elixir.Appsignal.increment_counter("glific.repo.db_connection_error", 1, %{
                   repo: :repo,
                   reason: "queue_timeout"
                 })
               )
      end
    end

    test "does not track non-connection errors" do
      with_mock Elixir.Appsignal,
                [:passthrough],
                add_distribution_value: fn _, _, _ -> :ok end,
                increment_counter: fn _, _, _ -> :ok end do
        assert query_event({:error, %Postgrex.Error{message: "syntax error"}}) == :ok

        refute called(
                 Elixir.Appsignal.increment_counter("glific.repo.db_connection_error", 1, :_)
               )
      end
    end

    test "does not track successful results" do
      with_mock Elixir.Appsignal,
                [:passthrough],
                add_distribution_value: fn _, _, _ -> :ok end,
                increment_counter: fn _, _, _ -> :ok end do
        assert query_event({:ok, %{rows: []}}) == :ok

        refute called(
                 Elixir.Appsignal.increment_counter("glific.repo.db_connection_error", 1, :_)
               )
      end
    end

    test "handles missing result key gracefully" do
      with_mock Elixir.Appsignal,
                [:passthrough],
                add_distribution_value: fn _, _, _ -> :ok end,
                increment_counter: fn _, _, _ -> :ok end do
        result =
          Appsignal.handle_event(
            [:glific, :repo, :query],
            %{queue_time: 1_000_000},
            %{query: "SELECT 1"},
            nil
          )

        assert result == :ok

        refute called(
                 Elixir.Appsignal.increment_counter("glific.repo.db_connection_error", 1, :_)
               )
      end
    end
  end
end
