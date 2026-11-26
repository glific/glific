defmodule Glific.Task.Supervisor do
  @moduledoc """
  Runs functions under a task supervisor with the caller's Logger metadata.

  A spawned process starts with empty Logger metadata, so anything it logs (including its own
  crash report) would lose `org_id`, `user_id` and `request_id`. Each function here copies the
  caller's metadata into the task before running it. Start every task through this module, not
  `Task` or `Task.Supervisor` directly; the `GlificCredo.Checks.SupervisedTask` check enforces it.

  Tasks run under `Glific.TaskSupervisor`. The stream functions take a `:supervisor` option to run
  under another one (for example `Glific.Broadcast.Supervisor`); every other option is passed
  through unchanged.

      Glific.Task.Supervisor.start_child(fn -> work() end)
  """

  require Logger

  @supervisor Glific.TaskSupervisor

  @doc "Starts a fire-and-forget task, like `Task.Supervisor.start_child/2`."
  @spec start_child((-> any())) :: DynamicSupervisor.on_start_child()
  def start_child(fun) when is_function(fun, 0),
    do: Task.Supervisor.start_child(@supervisor, with_metadata(fun))

  @doc "Starts a task linked to the caller, to be awaited, like `Task.Supervisor.async/2`."
  @spec async((-> any())) :: Task.t()
  def async(fun) when is_function(fun, 0),
    do: Task.Supervisor.async(@supervisor, with_metadata(fun))

  @doc "Starts a task not linked to the caller, like `Task.Supervisor.async_nolink/2`."
  @spec async_nolink((-> any())) :: Task.t()
  def async_nolink(fun) when is_function(fun, 0),
    do: Task.Supervisor.async_nolink(@supervisor, with_metadata(fun))

  @doc "Maps `fun` over `enumerable` concurrently, like `Task.Supervisor.async_stream/4`."
  @spec async_stream(Enumerable.t(), (any() -> any()), Keyword.t()) :: Enumerable.t()
  def async_stream(enumerable, fun, opts \\ []) when is_function(fun, 1) do
    {supervisor, opts} = Keyword.pop(opts, :supervisor, @supervisor)
    Task.Supervisor.async_stream(supervisor, enumerable, with_metadata(fun), opts)
  end

  @doc "Maps `fun` over `enumerable` in tasks not linked to the caller, like `Task.Supervisor.async_stream_nolink/4`."
  @spec async_stream_nolink(Enumerable.t(), (any() -> any()), Keyword.t()) :: Enumerable.t()
  def async_stream_nolink(enumerable, fun, opts \\ []) when is_function(fun, 1) do
    {supervisor, opts} = Keyword.pop(opts, :supervisor, @supervisor)
    Task.Supervisor.async_stream_nolink(supervisor, enumerable, with_metadata(fun), opts)
  end

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
