defmodule Glific.AppsignalTest do
  use Glific.DataCase

  import Mock

  alias Glific.Appsignal

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

  describe "handle_event [:oban, :job, _] inbound hold time" do
    defp job_event(event, queue, held_seconds) do
      inserted_at = DateTime.utc_now()

      job = %Oban.Job{
        args: %{"organization_id" => 1},
        inserted_at: inserted_at,
        scheduled_at: DateTime.add(inserted_at, held_seconds)
      }

      meta = %{
        id: 1,
        queue: queue,
        worker: "TestWorker",
        args: job.args,
        job: job,
        attempt: 1,
        max_attempts: 1,
        kind: :error,
        error: %RuntimeError{message: "boom"},
        stacktrace: []
      }

      measurement = %{queue_time: 0, duration: 0}

      with_mock Elixir.Appsignal, [:passthrough], add_distribution_value: fn _, _, _ -> :ok end do
        Appsignal.handle_event([:oban, :job, event], measurement, meta, nil)

        called(
          Elixir.Appsignal.add_distribution_value("inbound_job_hold_time", 3.0, %{
            organization_id: "1"
          })
        )
      end
    end

    test "records the hold time of a held inbound job that completes" do
      assert job_event(:stop, "gupshup_inbound", 3)
    end

    test "records the hold time of a held inbound job that fails" do
      assert job_event(:exception, "gupshup_inbound", 3)
    end

    test "records nothing for an inbound job that was never held" do
      refute job_event(:stop, "gupshup_inbound", 0)
    end

    test "records nothing for jobs on other queues" do
      refute job_event(:stop, "default", 3)
    end
  end

  describe "send_oban_queue_size/0" do
    test "executes without error" do
      assert Appsignal.send_oban_queue_size() == :ok
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

  describe "send_repo_pool_metrics/0" do
    test "reports connections in use and waiting callers per repo, summed across pool sources" do
      pool_size = Ecto.Adapter.lookup_meta(Glific.Repo).opts[:pool_size]
      replica_pool_size = Ecto.Adapter.lookup_meta(Glific.RepoReplica).opts[:pool_size]

      with_mocks([
        {Elixir.Appsignal, [:passthrough], add_distribution_value: fn _, _, _ -> :ok end},
        {DBConnection, [:passthrough],
         get_connection_metrics: fn _, _ ->
           [
             %{source: {:pool, self()}, ready_conn_count: 2, checkout_queue_length: 3},
             %{source: {:proxy, self()}, ready_conn_count: 1, checkout_queue_length: 1}
           ]
         end}
      ]) do
        assert Appsignal.send_repo_pool_metrics() == :ok

        assert called(
                 Elixir.Appsignal.add_distribution_value(
                   "glific.repo.pool.in_use",
                   pool_size - 3,
                   %{repo: :repo}
                 )
               )

        assert called(
                 Elixir.Appsignal.add_distribution_value(
                   "glific.repo.pool.in_use",
                   replica_pool_size - 3,
                   %{repo: :repo_replica}
                 )
               )

        assert called(
                 Elixir.Appsignal.add_distribution_value(
                   "glific.repo.pool.checkout_queue_length",
                   4,
                   %{repo: :repo}
                 )
               )

        assert called(
                 Elixir.Appsignal.add_distribution_value(
                   "glific.repo.pool.checkout_queue_length",
                   4,
                   %{repo: :repo_replica}
                 )
               )
      end
    end

    test "never reports a negative in_use count" do
      with_mocks([
        {Elixir.Appsignal, [:passthrough], add_distribution_value: fn _, _, _ -> :ok end},
        {DBConnection, [:passthrough],
         get_connection_metrics: fn _, _ ->
           [%{source: {:pool, self()}, ready_conn_count: 10_000, checkout_queue_length: 0}]
         end}
      ]) do
        assert Appsignal.send_repo_pool_metrics() == :ok

        assert called(Elixir.Appsignal.add_distribution_value("glific.repo.pool.in_use", 0, :_))
      end
    end

    test "returns :ok without reporting when the pool cannot be reached" do
      with_mocks([
        {Elixir.Appsignal, [:passthrough], add_distribution_value: fn _, _, _ -> :ok end},
        {DBConnection, [:passthrough], get_connection_metrics: fn _, _ -> exit(:noproc) end}
      ]) do
        assert Appsignal.send_repo_pool_metrics() == :ok
        refute called(Elixir.Appsignal.add_distribution_value(:_, :_, :_))
      end
    end
  end
end
