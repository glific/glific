defmodule Glific.Task.Supervisor do
  @moduledoc """
  Runs functions under `Glific.TaskSupervisor` with the caller's Logger metadata.

  A spawned process starts with empty Logger metadata, so anything it logs (including its own
  crash report) would lose `org_id`, `user_id` and `request_id`. Each function here copies the
  caller's metadata into the task before running it.

      Glific.Task.Supervisor.start_child(fn -> work() end)
  """

  require Logger

  @supervisor Glific.TaskSupervisor

  @doc "Starts a fire-and-forget task, like `Task.Supervisor.start_child/2`."
  @spec start_child((-> any())) :: DynamicSupervisor.on_start_child()
  def start_child(fun) when is_function(fun, 0),
    do: Task.Supervisor.start_child(@supervisor, with_metadata(fun))

  @doc "Starts a task not linked to the caller, like `Task.Supervisor.async_nolink/2`."
  @spec async_nolink((-> any())) :: Task.t()
  def async_nolink(fun) when is_function(fun, 0),
    do: Task.Supervisor.async_nolink(@supervisor, with_metadata(fun))

  @doc "Maps `fun` over `enumerable` concurrently, like `Task.Supervisor.async_stream/4`."
  @spec async_stream(Enumerable.t(), (any() -> any()), Keyword.t()) :: Enumerable.t()
  def async_stream(enumerable, fun, opts \\ []) when is_function(fun, 1),
    do: Task.Supervisor.async_stream(@supervisor, enumerable, with_metadata(fun), opts)

  @spec with_metadata((-> any()) | (any() -> any())) :: (-> any()) | (any() -> any())
  defp with_metadata(fun) when is_function(fun, 0) do
    metadata = Logger.metadata()

    fn ->
      Logger.metadata(metadata)
      fun.()
    end
  end

  defp with_metadata(fun) when is_function(fun, 1) do
    metadata = Logger.metadata()

    fn arg ->
      Logger.metadata(metadata)
      fun.(arg)
    end
  end
end
