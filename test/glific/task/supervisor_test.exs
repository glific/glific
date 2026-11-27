defmodule Glific.Task.SupervisorTest do
  use Glific.DataCase

  import ExUnit.CaptureLog

  setup do
    level = Logger.level()
    Logger.configure(level: :error)
    on_exit(fn -> Logger.configure(level: level) end)
    :ok
  end

  defp wait_until_down({:ok, pid}) do
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
  end

  test "async_nolink/1 runs with the caller's logger metadata", %{
    organization_id: organization_id
  } do
    task = Glific.Task.Supervisor.async_nolink(fn -> Logger.metadata()[:org_id] end)

    assert Task.await(task) == organization_id
  end

  test "async_stream/3 runs every element with the caller's logger metadata", %{
    organization_id: organization_id
  } do
    results =
      [1, 2]
      |> Glific.Task.Supervisor.async_stream(fn number ->
        {number, Logger.metadata()[:org_id]}
      end)
      |> Enum.map(fn {:ok, result} -> result end)

    assert results == [{1, organization_id}, {2, organization_id}]
  end

  test "async/1 runs with the caller's logger metadata", %{organization_id: organization_id} do
    task = Glific.Task.Supervisor.async(fn -> Logger.metadata()[:org_id] end)

    assert Task.await(task) == organization_id
  end

  test "async_stream_nolink/3 runs every element with the caller's logger metadata under the given supervisor",
       %{organization_id: organization_id} do
    results =
      [1, 2]
      |> Glific.Task.Supervisor.async_stream_nolink(
        fn number ->
          [supervisor | _ancestors] = Process.get(:"$ancestors")
          {number, Logger.metadata()[:org_id], supervisor}
        end,
        supervisor: Glific.Broadcast.Supervisor
      )
      |> Enum.map(fn {:ok, result} -> result end)

    broadcast_supervisor = Process.whereis(Glific.Broadcast.Supervisor)

    assert results == [
             {1, organization_id, broadcast_supervisor},
             {2, organization_id, broadcast_supervisor}
           ]
  end

  test "an error raised inside a task logs with org_id", %{organization_id: organization_id} do
    log =
      capture_log(fn ->
        wait_until_down(
          Glific.Task.Supervisor.start_child(fn -> raise "flow processing failed" end)
        )
      end)

    assert log =~ "flow processing failed"
    assert log =~ "org_id=#{organization_id}"
  end
end
