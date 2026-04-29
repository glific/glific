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
end
