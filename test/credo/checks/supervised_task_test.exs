Code.require_file("../../../.credo/checks/supervised_task.ex", __DIR__)

defmodule GlificCredo.Checks.SupervisedTaskTest do
  use ExUnit.Case, async: true

  alias GlificCredo.Checks.SupervisedTask

  setup_all do
    {:ok, _} = Application.ensure_all_started(:credo)
    :ok
  end

  defp issues(body, filename \\ "lib/glific/sample.ex", module \\ "Glific.Sample") do
    """
    defmodule #{module} do
      def run(items) do
        #{body}
      end
    end
    """
    |> Credo.SourceFile.parse(filename)
    |> SupervisedTask.run([])
  end

  test "flags tasks started with Task directly" do
    assert [_] = issues("Task.async(fn -> :ok end)")
    assert [_] = issues("Task.start(fn -> :ok end)")
    assert [_] = issues("Task.async_stream(items, fn item -> item end)")
    assert [_] = issues("items |> Task.async_stream(fn item -> item end)")
    assert [_] = issues("Enum.map(items, &Task.async(fn -> &1 end))")
  end

  test "flags tasks started with Task.Supervisor directly" do
    assert [_] = issues("Task.Supervisor.start_child(Glific.TaskSupervisor, fn -> :ok end)")
    assert [_] = issues("Task.Supervisor.async_nolink(Glific.TaskSupervisor, fn -> :ok end)")

    assert [_] =
             issues(
               "Task.Supervisor.async_stream_nolink(Glific.Broadcast.Supervisor, items, & &1)"
             )
  end

  test "does not flag Glific.Task.Supervisor or reading task results" do
    assert [] = issues("Glific.Task.Supervisor.start_child(fn -> :ok end)")
    assert [] = issues("Glific.Task.Supervisor.async_stream_nolink(items, & &1)")
    assert [] = issues("Task.await(items)")
    assert [] = issues("Task.await_many(items, 1_000)")
    assert [] = issues("Task.yield_many(items)")
  end

  test "does not flag test files or the wrapper module" do
    assert [] = issues("Task.async(fn -> :ok end)", "test/glific/sample_test.exs")

    assert [] =
             issues(
               "Task.Supervisor.start_child(Glific.TaskSupervisor, fn -> :ok end)",
               "lib/glific/task/supervisor.ex",
               "Glific.Task.Supervisor"
             )
  end
end
