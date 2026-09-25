defmodule GlificCredo.Checks.NoRawInspect do
  @moduledoc """
  Custom Credo check that forbids raw `inspect/1,2` in non-test production code.

  Raw `inspect/1` and `inspect/2` write the *full* term to logs and error
  strings, which can leak sensitive runtime state (auth tokens, phone numbers,
  the live `Authorization: Bearer …` header carried in a `%Tesla.Env{}`, …).
  Code must use `Glific.SafeLog.safe_inspect/1` instead, which behaves like
  `inspect/1` for ordinary terms but strips those sensitive fields first.

  The check walks each source file's AST and flags both the bare `inspect(...)`
  and the fully-qualified `Kernel.inspect(...)` call forms. Test files and any
  module listed in the `:excluded_modules` param (by default `Glific.SafeLog`,
  the wrapper itself) are exempt.

  See the [Credo guide on adding checks](https://credo.hexdocs.pm/adding_checks.html).
  """

  use Credo.Check,
    id: "GL1001",
    base_priority: :high,
    category: :warning,
    param_defaults: [excluded_modules: ["Glific.SafeLog"]],
    explanations: [
      check: """
      Raw `inspect/1` and `inspect/2` write the *full* term — including
      credentials and other P2 data — to logs and error strings. A call such as

          Logger.info("contact: \#{inspect(contact)}")

      can leak sensitive runtime state (auth tokens, phone numbers, …).

      Use `Glific.SafeLog.safe_inspect/1` instead. It behaves like `inspect/1`
      for ordinary terms but strips sensitive fields (e.g. the live
      `Authorization: Bearer …` header carried in a `%Tesla.Env{}`) before
      formatting.

      The only module allowed to call raw `inspect/1,2` is `Glific.SafeLog`
      itself, which implements the safe wrapper.
      """,
      params: [
        excluded_modules: "Modules permitted to call raw `inspect/1,2`."
      ]
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

  # Test code never reaches production logs, so raw `inspect/1,2` is allowed
  # there (and is idiomatic in assertions and test names).
  defp test_file?(%SourceFile{filename: filename}) do
    filename =~ ~r{(^|/)test/}
  end

  # A file is exempt when it defines one of the excluded modules (e.g. the
  # `Glific.SafeLog` wrapper itself).
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

  # Bare `inspect(...)` — i.e. `Kernel.inspect/1,2` imported by default.
  defp traverse({:inspect, meta, args} = ast, issues, issue_meta)
       when is_list(args) and length(args) in 1..2 do
    {ast, [issue_for(issue_meta, meta) | issues]}
  end

  # Fully-qualified `Kernel.inspect(...)`.
  defp traverse(
         {{:., _, [{:__aliases__, meta, [:Kernel]}, :inspect]}, _, args} = ast,
         issues,
         issue_meta
       )
       when is_list(args) and length(args) in 1..2 do
    {ast, [issue_for(issue_meta, meta) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, meta) do
    format_issue(
      issue_meta,
      message:
        "Use `Glific.SafeLog.safe_inspect/1` instead of raw `inspect/1` so sensitive values are never written to logs.",
      trigger: "inspect",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
