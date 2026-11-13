defmodule Glific.ErrorLogCounterTest do
  use Glific.DataCase

  import ExUnit.CaptureLog
  import Mock

  alias Glific.{ErrorLogCounter, LogContext}

  setup do
    level = Logger.level()
    Logger.configure(level: :error)
    on_exit(fn -> Logger.configure(level: level) end)
    :ok
  end

  test "attach/0 adds the handler once and is safe to call again" do
    :logger.remove_handler(:glific_error_log_counter)

    assert ErrorLogCounter.attach() == :ok
    assert :glific_error_log_counter in :logger.get_handler_ids()
    assert ErrorLogCounter.attach() == :ok
  end

  test "log/2 tags the counter with the event's org_id" do
    with_mock Appsignal, [:passthrough], increment_counter: fn _, _, _ -> :ok end do
      assert ErrorLogCounter.log(%{level: :error, meta: %{org_id: 5}, msg: {:string, "x"}}, %{}) ==
               :ok

      assert ErrorLogCounter.log(%{level: :error, meta: %{}, msg: {:string, "x"}}, %{}) == :ok

      assert called(Appsignal.increment_counter("error_log_count", 1, %{organization_id: "5"}))

      assert called(
               Appsignal.increment_counter("error_log_count", 1, %{organization_id: "unknown"})
             )
    end
  end

  test "log/2 never raises, so :logger keeps the handler attached" do
    with_mock Appsignal, [:passthrough], increment_counter: fn _, _, _ -> raise "nif down" end do
      assert ErrorLogCounter.log(%{level: :error, meta: %{org_id: 5}, msg: {:string, "x"}}, %{}) ==
               :ok
    end
  end

  test "a crash inside a wrapped task is counted against its organization", %{
    organization_id: organization_id
  } do
    organization_tag = to_string(organization_id)

    with_mock Appsignal, [:passthrough], increment_counter: fn _, _, _ -> :ok end do
      capture_log(fn ->
        {:ok, pid} =
          Task.Supervisor.start_child(
            Glific.TaskSupervisor,
            LogContext.wrap(fn -> raise "flow processing failed" end)
          )

        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
      end)

      assert called(
               Appsignal.increment_counter("error_log_count", 1, %{
                 organization_id: organization_tag
               })
             )
    end
  end
end
