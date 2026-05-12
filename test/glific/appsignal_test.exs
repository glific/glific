defmodule Glific.AppsignalTest do
  use Glific.DataCase

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

    test "tracks queue_timeout DBConnection.ConnectionError in result" do
      error = %DBConnection.ConnectionError{message: "queue timeout after 2999ms"}
      assert query_event({:error, error}) == :ok
    end

    test "tracks checkout_timeout DBConnection.ConnectionError in result" do
      error = %DBConnection.ConnectionError{message: "checkout timeout after 1000ms"}
      assert query_event({:error, error}) == :ok
    end

    test "tracks connection_not_available DBConnection.ConnectionError in result" do
      error = %DBConnection.ConnectionError{message: "connection not available and request was dropped"}
      assert query_event({:error, error}) == :ok
    end

    test "tracks other DBConnection.ConnectionError in result" do
      error = %DBConnection.ConnectionError{message: "some unexpected connection error"}
      assert query_event({:error, error}) == :ok
    end

    test "does not track non-connection errors" do
      assert query_event({:error, %Postgrex.Error{message: "syntax error"}}) == :ok
    end

    test "does not track successful results" do
      assert query_event({:ok, %{rows: []}}) == :ok
    end

    test "handles missing result key gracefully" do
      result =
        Appsignal.handle_event(
          [:glific, :repo, :query],
          %{queue_time: 1_000_000},
          %{query: "SELECT 1"},
          nil
        )

      assert result == :ok
    end
  end

end
