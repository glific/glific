defmodule Glific.LogContextTest do
  use Glific.DataCase

  import ExUnit.CaptureLog

  alias Glific.{Contacts.Contact, Flows.Broadcast, LogContext, Repo, RepoReplica}

  setup do
    level = Logger.level()
    Logger.configure(level: :error)
    on_exit(fn -> Logger.configure(level: level) end)
    :ok
  end

  defp run_and_wait(fun) do
    {:ok, pid} = Task.Supervisor.start_child(Glific.TaskSupervisor, fun)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
  end

  describe "wrap/1" do
    test "carries the caller's org, user and logger metadata into a spawned task", %{
      organization_id: organization_id
    } do
      Logger.metadata(request_id: "req-123")
      user = Repo.get_current_user()

      context =
        LogContext.wrap(fn ->
          {Repo.get_organization_id(), RepoReplica.get_organization_id(), Repo.get_current_user(),
           Logger.metadata()}
        end)
        |> Task.async()
        |> Task.await()

      assert {^organization_id, ^organization_id, ^user, metadata} = context
      assert metadata[:org_id] == organization_id
      assert metadata[:request_id] == "req-123"
    end

    test "wraps 1-arity functions for async streams", %{organization_id: organization_id} do
      results =
        [1, 2]
        |> Task.async_stream(LogContext.wrap(fn n -> {n, Logger.metadata()[:org_id]} end))
        |> Enum.map(fn {:ok, result} -> result end)

      assert results == [{1, organization_id}, {2, organization_id}]
    end

    test "an error raised inside a spawned task logs with org_id", %{
      organization_id: organization_id
    } do
      log =
        capture_log(fn ->
          run_and_wait(LogContext.wrap(fn -> raise "flow processing failed" end))
        end)

      assert log =~ "flow processing failed"
      assert log =~ "org_id=#{organization_id}"
    end

    test "without wrap/1 the spawned task's error has no org_id" do
      log = capture_log(fn -> run_and_wait(fn -> raise "flow processing failed" end) end)

      assert log =~ "flow processing failed"
      refute log =~ "org_id="
    end
  end

  describe "Oban job start handler" do
    test "tags the job process with the organization in its args" do
      task =
        Task.async(fn ->
          LogContext.handle_event(
            [:oban, :job, :start],
            %{},
            %{args: %{"organization_id" => 7}},
            []
          )

          Logger.metadata()[:org_id]
        end)

      assert Task.await(task) == 7
    end

    test "leaves metadata alone when the args carry no organization" do
      task =
        Task.async(fn ->
          LogContext.handle_event([:oban, :job, :start], %{}, %{args: %{"foo" => 1}}, [])
          Logger.metadata()[:org_id]
        end)

      assert Task.await(task) == nil
    end

    test "job_organization_id/1 reads top-level and nested organization ids" do
      assert LogContext.job_organization_id(%{"organization_id" => 1}) == 1
      assert LogContext.job_organization_id(%{"message" => %{"organization_id" => 2}}) == 2
      assert LogContext.job_organization_id(%{"media" => %{"organization_id" => 3}}) == 3
      assert LogContext.job_organization_id(%{"organization_id" => nil}) == nil
      assert LogContext.job_organization_id(%{}) == nil
    end
  end

  describe "broadcast task timeouts" do
    test "are logged as errors with org_id", %{organization_id: organization_id} do
      log =
        capture_log(fn ->
          Broadcast.log_task_timeouts(
            [
              {:ok, :ok},
              {:exit, {%Contact{id: 11}, :timeout}},
              {:exit, {42, :timeout}},
              {:exit, {%Contact{id: 12}, :killed}}
            ],
            organization_id
          )
        end)

      assert log =~ "org_id=#{organization_id}"
      assert log =~ "Broadcast task timed out for contact_id: 11"
      assert log =~ "Broadcast task timed out for wa_group_id: 42"
      refute log =~ "contact_id: 12"
    end
  end
end
