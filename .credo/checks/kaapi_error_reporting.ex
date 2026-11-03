defmodule GlificCredo.Checks.KaapiErrorReporting do
  @moduledoc """
  Custom Credo check that forbids reporting to AppSignal from code that calls the Kaapi client.

  `Glific.ThirdParty.Kaapi` reports every failed call itself, and it is the one place that decides
  what reaches AppSignal: a rejection of what the user entered (409, 422) is only logged, anything
  else is reported. A caller that reports the `{:error, reason}` it gets back reports it a second
  time and, worse, without that filter, so a duplicate assistant name lands in AppSignal again.

  The check flags `Glific.log_exception`, `Glific.log_error`, `Appsignal.send_error` and
  `Appsignal.error` inside any function clause that calls the Kaapi client, either directly
  (`Kaapi.create_collection(...)`) or through another function of the same module that does.

  The check is best-effort: it reads syntax, not data flow, so it misses a Kaapi result handed to
  a function that does not call Kaapi itself (`Kaapi.x() |> handle_result()`), and calls made
  through another module. A clause that calls Kaapi and must report a failure unrelated to it
  (say, a database lookup) disables the check on that line with a comment saying why. Test files
  and the Kaapi client modules are exempt.

  See the [Credo guide on adding checks](https://credo.hexdocs.pm/adding_checks.html).
  """

  use Credo.Check,
    id: "GL1003",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      A failure returned by the Kaapi client has already been reported by the client:

          case Kaapi.create_assistant_config(config, organization_id) do
            {:error, reason} ->
              Glific.log_exception(%Error{message: "...", reason: safe_inspect(reason)})

      reports it twice, and bypasses the client's rule that a user-input rejection (409, 422) is
      only logged. Handle the error (update state, return a message) without reporting it.
      """
    ]

  @client_module "Glific.ThirdParty.Kaapi"
  @kaapi_aliases [[:Kaapi], [:Glific, :ThirdParty, :Kaapi]]
  @reporters %{Glific: [:log_exception, :log_error], Appsignal: [:send_error, :error]}

  @doc false
  @impl true
  @spec run(Credo.SourceFile.t(), Keyword.t()) :: [Credo.Issue.t()]
  def run(%SourceFile{} = source_file, params) do
    if test_file?(source_file) or client_file?(source_file) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&collect_functions/2, [])
      |> issues(issue_meta)
    end
  end

  defp test_file?(%SourceFile{filename: filename}), do: filename =~ ~r{(^|/)test/}

  defp client_file?(source_file) do
    source_file
    |> Credo.Code.prewalk(&collect_module_names/2, [])
    |> Enum.any?(&(&1 == @client_module or String.starts_with?(&1, @client_module <> ".")))
  end

  defp collect_module_names({:defmodule, _, [{:__aliases__, _, parts}, _]} = ast, names)
       when is_list(parts) do
    if Enum.all?(parts, &is_atom/1),
      do: {ast, [Enum.map_join(parts, ".", &Atom.to_string/1) | names]},
      else: {ast, names}
  end

  defp collect_module_names(ast, names), do: {ast, names}

  defp collect_functions({kind, _, [head, body]} = ast, functions) when kind in [:def, :defp] do
    case function_name(head) do
      nil -> {ast, functions}
      name -> {ast, [{name, body} | functions]}
    end
  end

  defp collect_functions(ast, functions), do: {ast, functions}

  defp function_name({:when, _, [call | _guards]}), do: function_name(call)
  defp function_name({name, _, args}) when is_atom(name) and is_list(args), do: name
  defp function_name({name, _, context}) when is_atom(name) and is_atom(context), do: name
  defp function_name(_head), do: nil

  # Each clause is judged on its own: a clause that reports is flagged only when it reaches Kaapi.
  defp issues(clauses, issue_meta) do
    names = MapSet.new(clauses, &elem(&1, 0))

    summaries =
      Enum.map(clauses, fn {name, body} -> {name, summarize(body, names)} end)

    kaapi_callers = kaapi_callers(summaries)

    for {_name, %{reports: reports} = summary} <- summaries,
        reaches_kaapi?(summary, kaapi_callers),
        {reporter, meta} <- reports do
      issue_for(issue_meta, meta, reporter)
    end
  end

  defp reaches_kaapi?(%{kaapi?: true}, _kaapi_callers), do: true

  defp reaches_kaapi?(%{calls: calls}, kaapi_callers),
    do: not MapSet.disjoint?(calls, kaapi_callers)

  defp summarize(body, names) do
    {_ast, summary} =
      Macro.prewalk(body, %{kaapi?: false, calls: MapSet.new(), reports: []}, fn
        {{:., _, [{:__aliases__, meta, parts}, function]}, _, _args} = node, acc ->
          {node, record_remote_call(acc, parts, function, meta)}

        {name, _, args} = node, acc when is_atom(name) and is_list(args) ->
          {node, record_local_call(acc, name, names)}

        node, acc ->
          {node, acc}
      end)

    summary
  end

  defp record_remote_call(acc, parts, function, meta) do
    cond do
      parts in @kaapi_aliases ->
        %{acc | kaapi?: true}

      function in Map.get(@reporters, List.last(parts), []) and length(parts) == 1 ->
        %{acc | reports: [{"#{List.last(parts)}.#{function}", meta} | acc.reports]}

      true ->
        acc
    end
  end

  defp record_local_call(acc, name, names) do
    if MapSet.member?(names, name), do: %{acc | calls: MapSet.put(acc.calls, name)}, else: acc
  end

  # Functions of the module that call Kaapi, directly or through other functions of the module.
  defp kaapi_callers(summaries) do
    direct = for {name, %{kaapi?: true}} <- summaries, into: MapSet.new(), do: name
    expand_callers(direct, summaries)
  end

  defp expand_callers(callers, summaries) do
    expanded =
      for {name, %{calls: calls}} <- summaries,
          not MapSet.disjoint?(calls, callers),
          into: callers,
          do: name

    if MapSet.equal?(expanded, callers), do: callers, else: expand_callers(expanded, summaries)
  end

  defp issue_for(issue_meta, meta, reporter) do
    format_issue(
      issue_meta,
      message:
        "`Glific.ThirdParty.Kaapi` already reports its own failures; do not call `#{reporter}` in a function that calls Kaapi.",
      trigger: reporter,
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
