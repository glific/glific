defmodule GlificCredo.Checks.SupervisedTask do
  @moduledoc """
  Custom Credo check that forbids starting a task with `Task` or `Task.Supervisor` directly.

  A spawned process starts with empty Logger metadata, so its logs and its crash report lose
  `org_id`, `user_id` and `request_id`. `Glific.Task.Supervisor` copies the caller's metadata into
  the task, so every task must start through it.

  The check flags calls to `Task.async`, `Task.async_stream`, `Task.start` and every
  `Task.Supervisor` function that starts a task, called directly, piped or captured
  (`&Task.async(...)`). Reading a task's result (`Task.await`, `Task.yield_many`, ...) is not
  flagged.

  Test files and the modules in `:excluded_modules` (by default `Glific.Task.Supervisor`, which
  implements the wrapper) are exempt. Where a task genuinely must not run under a supervisor (for
  example one that reads the console with `IO.gets`), disable the check on that line with a comment
  saying why.

  See the [Credo guide on adding checks](https://credo.hexdocs.pm/adding_checks.html).
  """

  use Credo.Check,
    id: "GL1003",
    base_priority: :high,
    category: :warning,
    param_defaults: [excluded_modules: ["Glific.Task.Supervisor"]],
    explanations: [
      check: """
      A task started with

          Task.async(fn -> work() end)
          Task.Supervisor.start_child(Glific.TaskSupervisor, fn -> work() end)

      runs in a new process with empty Logger metadata, so its logs carry no `org_id`.

      Use `Glific.Task.Supervisor` instead (`start_child/1`, `async/1`, `async_nolink/1`,
      `async_stream/3`, `async_stream_nolink/3`). It copies the caller's Logger metadata into
      the task. Pass `supervisor:` to the stream functions to run under another supervisor.
      """,
      params: [
        excluded_modules: "Modules permitted to start tasks with `Task` directly."
      ]
    ]

  @task_functions [:async, :async_stream, :start]
  @supervisor_functions [
    :start_child,
    :async,
    :async_nolink,
    :async_stream,
    :async_stream_nolink
  ]

  @doc false
  @impl true
  @spec run(Credo.SourceFile.t(), Keyword.t()) :: [Credo.Issue.t()]
  def run(%SourceFile{} = source_file, params) do
    excluded_modules = Params.get(params, :excluded_modules, __MODULE__)

    if test_file?(source_file) or excluded_file?(source_file, excluded_modules) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  defp test_file?(%SourceFile{filename: filename}) do
    filename =~ ~r{(^|/)test/}
  end

  defp excluded_file?(source_file, excluded_modules) do
    source_file
    |> Credo.Code.prewalk(&collect_module_names/2, [])
    |> Enum.any?(&(&1 in excluded_modules))
  end

  defp collect_module_names({:defmodule, _, [{:__aliases__, _, parts}, _]} = ast, names)
       when is_list(parts) do
    if Enum.all?(parts, &is_atom/1) do
      {ast, [Enum.map_join(parts, ".", &Atom.to_string/1) | names]}
    else
      {ast, names}
    end
  end

  defp collect_module_names(ast, names), do: {ast, names}

  defp traverse({{:., _, [{:__aliases__, meta, [:Task]}, function]}, _, _} = ast, issues, issue_meta)
       when function in @task_functions,
       do: {ast, [issue_for(issue_meta, meta, "Task.#{function}") | issues]}

  defp traverse(
         {{:., _, [{:__aliases__, meta, [:Task, :Supervisor]}, function]}, _, _} = ast,
         issues,
         issue_meta
       )
       when function in @supervisor_functions,
       do: {ast, [issue_for(issue_meta, meta, "Task.Supervisor.#{function}") | issues]}

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, meta, trigger) do
    format_issue(
      issue_meta,
      message:
        "Start tasks with `Glific.Task.Supervisor` instead of `#{trigger}`, so the task keeps the caller's Logger metadata (`org_id`).",
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
