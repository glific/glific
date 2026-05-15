defmodule Glific.AppsignalTest do
  use Glific.DataCase

  import Mock

  alias Glific.Appsignal

  defp call_handle_event(args) do
    meta = %{queue: "default", worker: "TestWorker", args: args}
    measurement = %{queue_time: 1_500_000}
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
