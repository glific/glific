defmodule Glific.Flows.Expression do
  @moduledoc """
  Safe, non-Turing-complete evaluator for flow expressions.

  Flow authors embed small expressions in `<%= ... %>` tags inside flow content
  (router operands, wait timeouts, contact-field values, templating, ...). This
  module evaluates those expressions with a fixed, allowlisted vocabulary — it
  never hands user-influenced content to `EEx.eval_string/1` or
  `Code.eval_quoted/2`.

  ## Design

  1. **Split, don't parse.** Text outside `<%= ... %>` is opaque literal and is
     never parsed. NGO message copy ("Please apply for the scholarship") passes
     through untouched.
  2. **Interpret, don't eval.** We never call `Code.eval_quoted/2`. A syntactic
     allowlist over the *pre-expansion* AST is unsound, because `alias` rebinds
     names during macro expansion: `alias System, as: Timex` makes a hostile
     `Timex.cmd/2` node byte-identical to a legitimate `Timex.today/0` node.
     Validating one representation and executing another is the bug. We walk and
     execute the same tree.
  3. **Fail closed.** `eval_node/2` implements only the allowed node types. `alias`,
     `import`, `fn`, captures, computed modules and `apply/3` need no dedicated
     rule — they have no clause and fall to the catch-all, which rejects.
  4. **Modules resolve through `@mfa` only**, never Elixir's alias resolution.
     The module position must be a literal alias on the table.
  5. **Variables are data.** `@foo` reads from a bindings map; a value can never
     become code.

  ## Where the security guarantee lives

  `eval_node/2` (and its catch-all) is the **sole** security boundary. `safe_shape/1` is
  a cheap, deliberately permissive structural pre-check used at publish time for
  early author feedback — it is NOT a gate, and nothing that reaches `eval_node/2` may
  rely on it having run. Do not "optimise" by trusting `safe_shape/1` at runtime.

  ## Known limitations — anonymous functions

  `fn` and `&(...)` support is intentionally partial. None of these are security
  holes (a closure body is still interpreted through `eval_node`, so it can only
  run allowlisted operations), but they are gaps to close before this is
  considered complete:

    * **Only single-clause functions with simple variable params.** Multi-clause
      / pattern-matching functions (`fn 1 -> ...; _ -> ... end`), destructuring
      params (`fn {a, b} -> ... end`) and arity > 2 are rejected.
    * **No function-reference captures.** `&String.upcase/1` is rejected; it must
      be written `&String.upcase(&1)` or `fn x -> String.upcase(x) end`.
    * **Publish/runtime drift on arity (known bug).** `validate_ast/1` checks a
      closure's body but not its arity, so a 3-arg `fn` passes `validate/1` yet
      fails at runtime with "unsupported fn arity". This breaks the otherwise-held
      invariant that validation and evaluation agree; fix by arity-checking in
      `validate_ast/1`.
    * **The node cap does not bound closure work.** `@max_nodes` limits AST size,
      but `Enum.map(list, fn ...)` runs the body once per element, so a small AST
      can do work proportional to the list length. Runtime cost is still bounded
      by the `isolated/1` heap and timeout caps — not by `@max_nodes`.
  """

  # The complete set of callable functions, keyed `{alias, fun, arity}`.
  # Every entry must be pure, total, and cheap. Never add anything that evals
  # (`Code`/`EEx`), touches the OS (`System`/`File`/`:os`), reaches the `Repo`,
  # or can exhaust the atom table (`String.to_atom/1`).
  #
  # NOTE: `Timex.today/0` is mapped to `Date.utc_today/0` (UTC). If any real flow
  # depends on organisation-timezone semantics for `Timex.today()`, revisit this
  # during the Phase 0 corpus audit before enabling.
  @mfa %{
    # String
    {:String, :length, 1} => &String.length/1,
    {:String, :upcase, 1} => &String.upcase/1,
    {:String, :downcase, 1} => &String.downcase/1,
    {:String, :trim, 1} => &String.trim/1,
    {:String, :trim, 2} => &String.trim/2,
    {:String, :trim_leading, 2} => &String.trim_leading/2,
    {:String, :replace_leading, 3} => &String.replace_leading/3,
    {:String, :replace, 3} => &String.replace/3,
    {:String, :replace, 4} => &String.replace/4,
    {:String, :slice, 2} => &String.slice/2,
    {:String, :slice, 3} => &String.slice/3,
    {:String, :split, 2} => &String.split/2,
    {:String, :split, 3} => &String.split/3,
    {:String, :to_integer, 1} => &String.to_integer/1,
    {:String, :starts_with?, 2} => &String.starts_with?/2,
    {:String, :ends_with?, 2} => &String.ends_with?/2,
    {:String, :contains?, 2} => &String.contains?/2,
    # Decimal
    {:Decimal, :round, 2} => &Decimal.round/2,
    {:Decimal, :from_float, 1} => &Decimal.from_float/1,
    {:Decimal, :mult, 2} => &Decimal.mult/2,
    {:Decimal, :div, 2} => &Decimal.div/2,
    # Enum / List / Map
    {:Enum, :count, 1} => &Enum.count/1,
    {:Enum, :at, 2} => &Enum.at/2,
    {:Enum, :join, 1} => &Enum.join/1,
    {:Enum, :join, 2} => &Enum.join/2,
    # higher-order Enum functions. Safe because the predicate is one of our own
    # closures, whose body still only runs allowlisted operations.
    {:Enum, :find, 2} => &Enum.find/2,
    {:Enum, :any?, 2} => &Enum.any?/2,
    {:Enum, :all?, 2} => &Enum.all?/2,
    {:Enum, :filter, 2} => &Enum.filter/2,
    {:Enum, :reject, 2} => &Enum.reject/2,
    {:Enum, :map, 2} => &Enum.map/2,
    {:Enum, :at, 3} => &Enum.at/3,
    {:Enum, :slice, 2} => &Enum.slice/2,
    {:Enum, :find, 3} => &Enum.find/3,
    {:Enum, :sort_by, 2} => &Enum.sort_by/2,
    {:Enum, :sum, 1} => &Enum.sum/1,
    {:Enum, :map_join, 3} => &Enum.map_join/3,
    # NOTE: Enum.random/1 is NOT pure (non-deterministic). Included for the corpus
    # audit only; decide deliberately before enabling.
    {:Enum, :random, 1} => &Enum.random/1,
    {:List, :first, 1} => &List.first/1,
    {:List, :last, 1} => &List.last/1,
    {:List, :wrap, 1} => &List.wrap/1,
    {:Map, :get, 2} => &Map.get/2,
    {:Map, :get, 3} => &Map.get/3,
    # Integer / Float / URI / Jason
    {:Integer, :to_string, 1} => &Integer.to_string/1,
    {:Float, :parse, 1} => &Float.parse/1,
    {:URI, :encode, 1} => &URI.encode/1,
    {:Jason, :encode!, 1} => &Jason.encode!/1,
    # Date / Time / DateTime / NaiveDateTime
    {:Date, :utc_today, 0} => &Date.utc_today/0,
    {:Date, :to_string, 1} => &Date.to_string/1,
    {:Date, :diff, 2} => &Date.diff/2,
    {:Date, :add, 2} => &Date.add/2,
    {:Date, :compare, 2} => &Date.compare/2,
    {:Date, :days_in_month, 1} => &Date.days_in_month/1,
    {:Date, :from_iso8601!, 1} => &Date.from_iso8601!/1,
    {:Time, :diff, 3} => &Time.diff/3,
    {:Time, :from_iso8601!, 1} => &Time.from_iso8601!/1,
    {:DateTime, :utc_now, 0} => &DateTime.utc_now/0,
    {:DateTime, :diff, 2} => &DateTime.diff/2,
    {:DateTime, :diff, 3} => &DateTime.diff/3,
    {:DateTime, :after?, 2} => &DateTime.after?/2,
    {:DateTime, :to_unix, 1} => &DateTime.to_unix/1,
    {:DateTime, :from_naive!, 2} => &DateTime.from_naive!/2,
    {:DateTime, :now!, 1} => &DateTime.now!/1,
    {:NaiveDateTime, :diff, 3} => &NaiveDateTime.diff/3,
    {:NaiveDateTime, :compare, 2} => &NaiveDateTime.compare/2,
    {:NaiveDateTime, :from_iso8601!, 1} => &NaiveDateTime.from_iso8601!/1,
    {:Calendar, :strftime, 2} => &Calendar.strftime/2,
    {:DateTime, :to_date, 1} => &DateTime.to_date/1,
    {:DateTime, :to_string, 1} => &DateTime.to_string/1,
    {:DateTime, :to_iso8601, 1} => &DateTime.to_iso8601/1,
    {:DateTime, :add, 3} => &DateTime.add/3,
    {:DateTime, :from_iso8601, 1} => &DateTime.from_iso8601/1,
    {:NaiveDateTime, :new!, 2} => &NaiveDateTime.new!/2,
    {:DateTime, :new!, 3} => &DateTime.new!/3,
    # Timex (today/0 kept as UTC per the note above)
    {:Timex, :today, 0} => &Date.utc_today/0,
    {:Timex, :today, 1} => &Timex.today/1,
    {:Timex, :now, 0} => &Timex.now/0,
    {:Timex, :now, 1} => &Timex.now/1,
    {:Timex, :diff, 3} => &Timex.diff/3,
    {:Timex, :compare, 2} => &Timex.compare/2,
    {:Timex, :to_unix, 1} => &Timex.to_unix/1,
    {:Timex, :format!, 2} => &Timex.format!/2,
    {:Timex, :shift, 2} => &Timex.shift/2,
    {:Timex, :parse!, 2} => &Timex.parse!/2,
    {:Timex, :format!, 3} => &Timex.format!/3,
    {:Timex, :month_name, 1} => &Timex.month_name/1,
    {:Timex, :to_datetime, 2} => &Timex.to_datetime/2,
    {[:Timex, :Timezone], :convert, 2} => &Timex.Timezone.convert/2,
    # Regex — the sigil compiles author-authored patterns; runtime is bounded by
    # the isolated-process timeout (mitigates catastrophic-backtracking / ReDoS).
    {:Regex, :match?, 2} => &Regex.match?/2,
    {:Regex, :run, 2} => &Regex.run/2,
    {:Regex, :run, 3} => &Regex.run/3,
    {:Regex, :replace, 3} => &Regex.replace/3,
    {:Regex, :replace, 4} => &Regex.replace/4,
    {:Regex, :scan, 2} => &Regex.scan/2,
    # Glific flow helper. send_template/2 is PURE: it builds a JSON template
    # descriptor string and does NOT send anything (the flow engine sends later).
    # Each entry maps to the actual function the author named (the per-NGO
    # Clients.* modules currently just delegate to Glific.send_template/2, but we
    # call the real function so any future org-specific logic is honoured), keyed
    # by full alias path for the multi-segment modules.
    {:Glific, :send_template, 2} => &Glific.send_template/2,
    {[:Glific, :Clients, :PehlayAkshar], :send_template, 2} =>
      &Glific.Clients.PehlayAkshar.send_template/2,
    {[:Glific, :Clients, :DigitalGreen], :send_template, 2} =>
      &Glific.Clients.DigitalGreen.send_template/2,
    {[:Glific, :Clients, :ArogyaWorld], :template, 2} => &Glific.Clients.ArogyaWorld.template/2,
    {[:Glific, :Clients, :Tap], :template, 2} => &Glific.Clients.Tap.template/2,
    {[:Glific, :Clients, :Tap], :template, 1} => &Glific.Clients.Tap.template/1
  }

  # Operators / Kernel functions callable bare, as `{name, arity}`. Kept as plain
  # atoms rather than captures: `and`/`or`/`<>` are macros, so `&Kernel.and/2` is
  # not a capturable remote function. Dispatch is via `kernel_call/2` below.
  @kernel [
    {:+, 2},
    {:-, 2},
    {:*, 2},
    {:/, 2},
    {:-, 1},
    {:rem, 2},
    {:div, 2},
    {:abs, 1},
    {:round, 1},
    {:trunc, 1},
    {:elem, 2},
    {:length, 1},
    {:==, 2},
    {:!=, 2},
    {:>, 2},
    {:<, 2},
    {:>=, 2},
    {:<=, 2},
    {:<>, 2},
    {:not, 1},
    {:and, 2},
    {:or, 2},
    {:===, 2},
    {:!==, 2},
    {:!, 1},
    {:in, 2},
    {:to_string, 1},
    {:is_number, 1},
    {:is_binary, 1},
    {:is_integer, 1},
    {:is_nil, 1},
    {:max, 2},
    {:min, 2},
    {:then, 2},
    {:.., 2},
    {:hd, 1},
    {:is_map, 1}
  ]

  # Literal atoms that are safe to use as *values* — time units (for Date/Time/
  # DateTime/Timex diff & shift), comparison/ordering results, and a couple of
  # formatter/result flags. This is a curated positive list: module-name atoms
  # (`:os`, `:crypto`, `:rand`, `:erlang`, ...) are deliberately excluded, so a
  # bare atom can never name a module. (Even if one slipped in, a `:mod.fun(...)`
  # call has no eval_node clause and still rejects — this is defence in depth.)
  @safe_atoms [
    :microsecond,
    :millisecond,
    :second,
    :seconds,
    :minute,
    :minutes,
    :hour,
    :hours,
    :day,
    :days,
    :week,
    :weeks,
    :month,
    :months,
    :year,
    :years,
    :lt,
    :gt,
    :eq,
    :asc,
    :desc,
    :ok,
    :error,
    :strftime,
    # Regex.run/replace capture options
    :all,
    :first,
    :all_but_first
  ]

  # Resource limits. An interpreter prevents RCE, not resource exhaustion:
  # `2*2*2*...` builds bignums, and Glific runs a single BEAM node shared with
  # Oban and the web server.
  @max_nodes 300
  @max_output 10_000
  @timeout_ms 100
  @max_heap_words 200_000

  @expr_regex ~r/<%=(.*?)%>/s

  @typedoc "Bindings for `@var` lookups, string- or atom-keyed."
  @type binding :: %{optional(atom() | String.t()) => any()}

  @typedoc "A compiled template segment: literal text or a validated AST."
  @type segment :: {:text, String.t()} | {:expr, Macro.t()}

  @doc """
  Validate a template without evaluating it. Used at publish time so a bad
  expression is caught at authoring, not on a live contact's message.
  """
  @spec validate(String.t()) :: :ok | {:error, String.t()}
  def validate(template) when is_binary(template) do
    case compile(template) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @doc """
  Compile a template at publish time into segments of literal text and validated
  ASTs. Parsing happens HERE, once, on staff-authored input — never at runtime on
  a live contact's message. Cache the result alongside the flow revision.
  """
  @spec compile(String.t()) :: {:ok, [segment()]} | {:error, String.t()}
  def compile(template) when is_binary(template) do
    template
    |> segments()
    |> Enum.reduce_while({:ok, []}, fn
      {:text, text}, {:ok, acc} ->
        {:cont, {:ok, [{:text, text} | acc]}}

      {:expr, src}, {:ok, acc} ->
        with {:ok, ast} <- parse(src, false),
             :ok <- check_size(ast),
             :ok <- safe_shape(ast) do
          {:cont, {:ok, [{:expr, ast} | acc]}}
        else
          {:error, _} = err -> {:halt, err}
        end
    end)
    |> case do
      {:ok, segs} -> {:ok, Enum.reverse(segs)}
      err -> err
    end
  end

  @doc """
  Render a template compiled by `compile/1`. Performs NO parsing, so
  attacker-controlled data can never reach the parser. This is the runtime entry
  point once call sites pass bindings instead of pre-substituting.
  """
  @spec render([segment()], binding()) :: {:ok, String.t()} | {:error, String.t()}
  def render(compiled, bindings) when is_list(compiled) do
    compiled
    |> Enum.reduce_while({:ok, []}, fn
      {:text, text}, {:ok, acc} ->
        {:cont, {:ok, [text | acc]}}

      {:expr, ast}, {:ok, acc} ->
        case isolated(fn -> eval_node(ast, bindings) end) do
          {:ok, value} -> {:cont, {:ok, [to_output(value) | acc]}}
          {:error, _} = err -> {:halt, err}
        end
    end)
    |> case do
      {:ok, parts} -> finish(parts)
      err -> err
    end
  end

  @doc """
  Evaluate a template, substituting `<%= ... %>` with the interpreted result.
  Returns the rendered string. Any rejection degrades to an error tuple; the
  caller decides how to surface it.

  ## Examples

      iex> Glific.Flows.Expression.eval("<%= 4 + 4 %>")
      {:ok, "8"}

      iex> Glific.Flows.Expression.eval("You earned <%= rem(7, 3) %> points")
      {:ok, "You earned 1 points"}

      iex> match?({:error, _}, Glific.Flows.Expression.eval("<%= System.get_env() %>"))
      true
  """
  @spec eval(String.t(), binding()) :: {:ok, String.t()} | {:error, String.t()}
  def eval(template, bindings \\ %{}) when is_binary(template) do
    template
    |> segments()
    |> Enum.reduce_while({:ok, []}, fn
      {:text, text}, {:ok, acc} ->
        {:cont, {:ok, [text | acc]}}

      {:expr, src}, {:ok, acc} ->
        case eval_expr(src, bindings) do
          {:ok, value} -> {:cont, {:ok, [to_output(value) | acc]}}
          {:error, _} = err -> {:halt, err}
        end
    end)
    |> case do
      {:ok, parts} -> finish(parts)
      {:error, _} = err -> err
    end
  end

  @spec finish([String.t()]) :: {:ok, String.t()} | {:error, String.t()}
  defp finish(parts) do
    out = parts |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()

    if byte_size(out) > @max_output,
      do: {:error, "expression output too large"},
      else: {:ok, out}
  end

  # -- template splitting ---------------------------------------------------
  # Everything outside <%= %> is literal. We never parse prose.

  @spec segments(String.t()) :: [segment()]
  defp segments(template) do
    @expr_regex
    |> Regex.split(template, include_captures: true, trim: false)
    |> Enum.map(fn part ->
      case Regex.run(@expr_regex, part) do
        [^part, inner] -> {:expr, inner}
        _ -> {:text, part}
      end
    end)
  end

  # -- validation -----------------------------------------------------------

  # `atoms_only?` encodes the parse-time trust level, and the distinction is
  # load-bearing:
  #
  #   true  -- runtime parsing of already-substituted content. No identifiers
  #            survive substitution, so this cannot reject a legitimate
  #            expression, and it stops a hostile `@aaa.bbb` from growing the
  #            atom table (which the BEAM never GCs) on every inbound message.
  #   false -- publish-time parsing of staff-authored templates. Needed because
  #            NGO custom fields (@contact.fields.enrollment_status) are novel
  #            identifiers. Safe because publishing is human-paced and
  #            authenticated, so atom growth is bounded by the number of
  #            published expressions.
  @spec parse(String.t(), boolean()) :: {:ok, Macro.t()} | {:error, String.t()}
  defp parse(src, atoms_only?) do
    case Code.string_to_quoted(src, existing_atoms_only: atoms_only?) do
      {:ok, ast} -> {:ok, ast}
      {:error, _} -> {:error, "invalid expression syntax"}
    end
  rescue
    _ -> {:error, "invalid expression syntax"}
  end

  @spec check_size(Macro.t()) :: :ok | {:error, String.t()}
  defp check_size(ast) do
    {_, n} = Macro.prewalk(ast, 0, fn node, acc -> {node, acc + 1} end)
    if n > @max_nodes, do: {:error, "expression too complex"}, else: :ok
  end

  # Structural validation that mirrors eval_node/2's accepted node shapes exactly by
  # recursing top-down — never classifying a sub-node in isolation. Because it is
  # the structural twin of eval_node/2, `validate/1` cannot green-light anything eval_node/2
  # would reject: the two stay in lock-step and there is no publish-vs-runtime
  # drift. It cannot see runtime-only failures (division by zero, field access on
  # a non-map, unbound variable), which remain eval_node/2's responsibility.
  @spec safe_shape(Macro.t()) :: :ok | {:error, String.t()}
  defp safe_shape(ast), do: validate_ast(ast)

  @spec validate_ast(Macro.t()) :: :ok | {:error, String.t()}
  defp validate_ast(n)
       when is_integer(n) or is_float(n) or is_binary(n) or is_boolean(n) or is_nil(n),
       do: :ok

  defp validate_ast(n) when is_atom(n) do
    if n in @safe_atoms,
      do: :ok,
      else: {:error, "bare atom #{Glific.SafeLog.safe_inspect(n)}"}
  end

  defp validate_ast(l) when is_list(l), do: validate_all(l)

  defp validate_ast({:@, _, [{name, _, nil}]}) when is_atom(name), do: :ok

  defp validate_ast({name, _, nil}) when is_atom(name), do: :ok

  # remote call: only literal-alias modules on the @mfa table
  defp validate_ast({{:., _, [{:__aliases__, _, [m]}, f]}, _, args}) when is_list(args) do
    if Map.has_key?(@mfa, {m, f, length(args)}),
      do: validate_all(args),
      else: {:error, "#{m}.#{f}/#{length(args)}"}
  end

  # multi-segment module call (twin of the eval_node clause above)
  defp validate_ast({{:., _, [{:__aliases__, _, segments}, f]}, _, args})
       when is_list(segments) and length(segments) > 1 and is_list(args) do
    if Map.has_key?(@mfa, {segments, f, length(args)}),
      do: validate_all(args),
      else: {:error, "#{Enum.join(segments, ".")}.#{f}/#{length(args)}"}
  end

  # field access: inner must itself be a valid data expression (a var, @var or a
  # nested field chain) -- never a bare atom or module.
  defp validate_ast({{:., _, [inner, f]}, _, []}) when is_atom(f), do: validate_ast(inner)

  # control-flow forms — twins of the eval_node clauses, same order
  defp validate_ast({:if, _, [condition, branches]}) when is_list(branches) do
    with :ok <- validate_ast(condition),
         :ok <- validate_ast(Keyword.get(branches, :do)) do
      validate_ast(Keyword.get(branches, :else))
    end
  end

  defp validate_ast({:cond, _, [[{:do, clauses}]]}), do: validate_cond(clauses)

  defp validate_ast({:&&, _, [a, b]}), do: validate_all([a, b])
  defp validate_ast({:||, _, [a, b]}), do: validate_all([a, b])

  defp validate_ast({:|>, _, [left, right]}), do: validate_ast(inject_pipe(left, right))

  defp validate_ast({:__block__, _, stmts}), do: validate_block(stmts)

  defp validate_ast({:<<>>, _, parts}), do: validate_interp(parts)

  # literal regex sigil (twin of the eval_node clause; before the operator clause)
  defp validate_ast({:sigil_r, _, [{:<<>>, _, [pattern]}, _flags]}) when is_binary(pattern),
    do: :ok

  # calendar sigils ~T/~D/~N
  defp validate_ast({sigil, _, [{:<<>>, _, [str]}, _]})
       when sigil in [:sigil_T, :sigil_D, :sigil_N] and is_binary(str),
       do: :ok

  # ~s(...) string sigil — its first arg is the interpolation <<>>, validated
  # exactly like an ordinary interpolated string (the modifiers carry no
  # safety-relevant options; ~s only ever yields a binary).
  defp validate_ast({:sigil_s, _, [{:<<>>, _, parts}, _mods]}), do: validate_interp(parts)

  # map literal — validate non-atom keys and all values
  defp validate_ast({:%{}, _, pairs}) when is_list(pairs) do
    Enum.reduce_while(pairs, :ok, fn {k, v}, :ok ->
      with :ok <- validate_key(k),
           :ok <- validate_ast(v) do
        {:cont, :ok}
      else
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  # single-clause fn with simple params; the body is validated like any other
  # expression (param vars are bare vars, always structurally valid).
  defp validate_ast({:fn, _, [{:->, _, [params, body]}]}) when is_list(params) do
    if Enum.all?(params, &match?({name, _, nil} when is_atom(name), &1)),
      do: validate_ast(body),
      else: {:error, "unsupported fn parameter"}
  end

  defp validate_ast({:&, _, [n]}) when is_integer(n), do: :ok
  defp validate_ast({:&, _, [inner]}), do: validate_ast(inner)

  # operators / Kernel calls on the @kernel table
  defp validate_ast({op, _, args}) when is_atom(op) and is_list(args) do
    if {op, length(args)} in @kernel,
      do: validate_all(args),
      else: {:error, "#{op}/#{length(args)}"}
  end

  # keyword-list pair (twin of the eval_node clause) — validate only the value
  defp validate_ast({key, value}) when is_atom(key), do: validate_ast(value)

  defp validate_ast(node), do: {:error, "disallowed expression: #{safe_desc(node)}"}

  defp validate_cond(clauses) do
    Enum.reduce_while(clauses, :ok, fn
      {:->, _, [[condition], body]}, :ok ->
        case validate_all([condition, body]) do
          :ok -> {:cont, :ok}
          {:error, _} = err -> {:halt, err}
        end

      other, :ok ->
        {:halt, {:error, "disallowed cond clause #{safe_desc(other)}"}}
    end)
  end

  defp validate_block(stmts) do
    Enum.reduce_while(stmts, :ok, fn
      {:=, _, [{var, _, nil}, expr]}, :ok when is_atom(var) ->
        case validate_ast(expr) do
          :ok -> {:cont, :ok}
          {:error, _} = err -> {:halt, err}
        end

      stmt, :ok ->
        case validate_ast(stmt) do
          :ok -> {:cont, :ok}
          {:error, _} = err -> {:halt, err}
        end
    end)
  end

  defp validate_interp(parts) do
    Enum.reduce_while(parts, :ok, fn
      s, :ok when is_binary(s) ->
        {:cont, :ok}

      {:"::", _, [inner, _]}, :ok ->
        case validate_ast(unwrap_to_string(inner)) do
          :ok -> {:cont, :ok}
          {:error, _} = err -> {:halt, err}
        end

      other, :ok ->
        {:halt, {:error, "disallowed interpolation #{safe_desc(other)}"}}
    end)
  end

  @spec validate_all([Macro.t()]) :: :ok | {:error, String.t()}
  defp validate_all(nodes) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case validate_ast(node) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  # atom map keys are inert labels; any other key is a normal expression
  defp validate_key(k) when is_atom(k), do: :ok
  defp validate_key(k), do: validate_ast(k)

  # -- evaluation -----------------------------------------------------------

  # Phase 1 path: content has already been through MessageVarParser, so all
  # @vars are literals and `existing_atoms_only: true` is both safe and lossless.
  @spec eval_expr(String.t(), binding()) :: {:ok, any()} | {:error, String.t()}
  defp eval_expr(src, bindings) do
    with {:ok, ast} <- parse(src, true),
         :ok <- check_size(ast),
         :ok <- safe_shape(ast) do
      isolated(fn -> eval_node(ast, bindings) end)
    end
  end

  # Bounded: an interpreter prevents RCE, not runaway CPU/memory.
  @spec isolated((-> any())) :: {:ok, any()} | {:error, String.t()}
  defp isolated(fun) do
    parent = self()
    ref = make_ref()

    {pid, mon} =
      :erlang.spawn_opt(
        fn ->
          result =
            try do
              {:ok, fun.()}
            catch
              {:reject, why} -> {:error, why}
              _, _ -> {:error, "expression failed"}
            end

          send(parent, {ref, result})
        end,
        [:monitor, max_heap_size: %{size: @max_heap_words, kill: true, error_logger: false}]
      )

    receive do
      {^ref, result} ->
        Process.demonitor(mon, [:flush])
        result

      {:DOWN, ^mon, :process, ^pid, _reason} ->
        {:error, "expression exceeded resource limits"}
    after
      @timeout_ms ->
        Process.exit(pid, :kill)
        Process.demonitor(mon, [:flush])
        {:error, "expression timed out"}
    end
  end

  # literals
  defp eval_node(n, _)
       when is_integer(n) or is_float(n) or is_binary(n) or is_boolean(n) or is_nil(n),
       do: n

  defp eval_node(n, _) when is_atom(n) do
    if n in @safe_atoms, do: n, else: reject("bare atom #{Glific.SafeLog.safe_inspect(n)}")
  end

  defp eval_node(l, bindings) when is_list(l), do: Enum.map(l, &eval_node(&1, bindings))

  # EEx assign: @results -> bindings lookup. Data, never code.
  defp eval_node({:@, _, [{name, _, nil}]}, bindings) when is_atom(name),
    do: fetch(bindings, name)

  # bare var
  defp eval_node({name, _, nil}, bindings) when is_atom(name), do: fetch(bindings, name)

  # remote call: module MUST be a literal alias on the table. This is the only
  # path to a module, so alias/import/computed modules cannot reach one.
  defp eval_node({{:., _, [{:__aliases__, _, [m]}, f]}, _, args}, bindings) when is_list(args) do
    key = {m, f, length(args)}

    case Map.fetch(@mfa, key) do
      {:ok, fun} -> apply(fun, Enum.map(args, &eval_node(&1, bindings)))
      :error -> reject("#{m}.#{f}/#{length(args)}")
    end
  end

  # multi-segment module (e.g. Glific.Clients.PehlayAkshar) -- keyed by the literal
  # alias path. We concat nothing and never consult Elixir's alias table, so the
  # path is exactly what the author typed; the @mfa lookup is still the only gate.
  defp eval_node({{:., _, [{:__aliases__, _, segments}, f]}, _, args}, bindings)
       when is_list(segments) and length(segments) > 1 and is_list(args) do
    key = {segments, f, length(args)}

    case Map.fetch(@mfa, key) do
      {:ok, fun} -> apply(fun, Enum.map(args, &eval_node(&1, bindings)))
      :error -> reject("#{Enum.join(segments, ".")}.#{f}/#{length(args)}")
    end
  end

  # field access on plain maps only -- never structs, never modules
  defp eval_node({{:., _, [inner, key]}, _, []}, bindings) when is_atom(key) do
    case eval_node(inner, bindings) do
      m when is_map(m) and not is_struct(m) -> map_get(m, key)
      _ -> reject("field access on non-map")
    end
  end

  # -- control-flow special forms (branching only; still non-Turing-complete) --

  # if cond, do: x, else: y   (else optional)
  defp eval_node({:if, _, [condition, branches]}, bindings) when is_list(branches) do
    if truthy?(eval_node(condition, bindings)),
      do: eval_node(Keyword.get(branches, :do), bindings),
      else: eval_node(Keyword.get(branches, :else), bindings)
  end

  # cond do c -> body ... end
  defp eval_node({:cond, _, [[{:do, clauses}]]}, bindings), do: eval_cond(clauses, bindings)

  # short-circuit && / ||
  defp eval_node({:&&, _, [a, b]}, bindings) do
    va = eval_node(a, bindings)
    if truthy?(va), do: eval_node(b, bindings), else: va
  end

  defp eval_node({:||, _, [a, b]}, bindings) do
    va = eval_node(a, bindings)
    if truthy?(va), do: va, else: eval_node(b, bindings)
  end

  # pipe: a |> f(b)  ==  f(a, b). We rewrite the AST and interpret it -- never eval.
  defp eval_node({:|>, _, [left, right]}, bindings),
    do: eval_node(inject_pipe(left, right), bindings)

  # multi-statement block; `x = expr` binds x for later statements in the block.
  defp eval_node({:__block__, _, stmts}, bindings), do: eval_block(stmts, bindings)

  # string interpolation "a #{x} b"
  defp eval_node({:<<>>, _, parts}, bindings) do
    parts |> Enum.map(&interp_part(&1, bindings)) |> IO.iodata_to_binary()
  end

  # ~r/.../ literal regex sigil (no interpolation — an interpolated pattern has a
  # multi-part <<>> and falls through to the catch-all). Must precede the generic
  # operator clause, which would otherwise match {:sigil_r, _, args}.
  defp eval_node({:sigil_r, _, [{:<<>>, _, [pattern]}, flags]}, _bindings)
       when is_binary(pattern),
       do: Regex.compile!(pattern, List.to_string(flags))

  # literal calendar sigils ~T/~D/~N
  defp eval_node({sigil, _, [{:<<>>, _, [str]}, _]}, _bindings)
       when sigil in [:sigil_T, :sigil_D, :sigil_N] and is_binary(str),
       do: sigil_value(sigil, str)

  # ~s(...) string sigil — evaluate its interpolation <<>> exactly like an
  # ordinary interpolated string.
  defp eval_node({:sigil_s, _, [{:<<>>, _, parts}, _mods]}, bindings),
    do: eval_node({:<<>>, [], parts}, bindings)

  # map literal %{k => v, ...}. Atom keys are inert labels; other keys and all
  # values are interpreted through the allowlist.
  defp eval_node({:%{}, _, pairs}, bindings) when is_list(pairs) do
    Map.new(pairs, fn {k, v} -> {eval_key(k, bindings), eval_node(v, bindings)} end)
  end

  # single-clause anonymous function with simple (non-pattern) params. Produces a
  # real closure whose body is still interpreted through eval_node, so nothing
  # outside the allowlist can run inside it. Used by Enum.find/map/reject/then.
  # See "Known limitations — anonymous functions" in the @moduledoc for the
  # partial-support gaps (multi-clause, arity, function-ref captures, the
  # validate/runtime arity drift, and node-cap blindness).
  defp eval_node({:fn, _, [{:->, _, [params, body]}]}, bindings) when is_list(params) do
    build_closure(params, body, bindings)
  end

  # capture placeholder &1, &2, ...
  defp eval_node({:&, _, [n]}, bindings) when is_integer(n),
    do: Map.fetch!(bindings, {:capture, n})

  # anonymous-shorthand capture &(&1 > 3) -> a closure (function-ref captures like
  # &String.upcase/1 have no placeholder, hit make_capture(0, ...) and reject).
  defp eval_node({:&, _, [inner]}, bindings),
    do: make_capture(max_placeholder(inner, 0), inner, bindings)

  # allowed operators / Kernel calls
  defp eval_node({op, _, args}, bindings) when is_atom(op) and is_list(args) do
    if {op, length(args)} in @kernel,
      do: kernel_call(op, Enum.map(args, &eval_node(&1, bindings))),
      else: reject("#{op}/#{length(args)}")
  end

  # FAIL-CLOSED CATCH-ALL. alias, import, fn, &capture, spawn, apply/3,
  # __block__, sigils, computed modules all land here. No rule needed.
  # keyword-list pair, e.g. `days: 1` in Timex.shift(d, days: 1). The key is an
  # inert atom label (it can never name a module or be called); the value is
  # interpreted through the allowlist like anything else.
  defp eval_node({key, value}, bindings) when is_atom(key), do: {key, eval_node(value, bindings)}

  defp eval_node(node, _), do: reject(safe_desc(node))

  # Explicit dispatch. Args are already evaluated (strict), so using the
  # non-short-circuit :erlang BIFs for and/or/not matches our semantics.
  defp kernel_call(:+, [a, b]), do: a + b
  defp kernel_call(:-, [a, b]), do: a - b
  defp kernel_call(:-, [a]), do: -a
  defp kernel_call(:*, [a, b]), do: a * b
  defp kernel_call(:/, [_, 0]), do: reject("division by zero")
  defp kernel_call(:/, [_, +0.0]), do: reject("division by zero")
  defp kernel_call(:/, [a, b]), do: a / b
  defp kernel_call(:rem, [_, 0]), do: reject("division by zero")
  defp kernel_call(:rem, [a, b]), do: rem(a, b)
  defp kernel_call(:div, [_, 0]), do: reject("division by zero")
  defp kernel_call(:div, [a, b]), do: div(a, b)
  defp kernel_call(:abs, [a]), do: abs(a)
  defp kernel_call(:round, [a]), do: round(a)
  defp kernel_call(:trunc, [a]), do: trunc(a)
  defp kernel_call(:elem, [a, b]), do: elem(a, b)
  defp kernel_call(:length, [a]), do: length(a)
  defp kernel_call(:==, [a, b]), do: a == b
  defp kernel_call(:!=, [a, b]), do: a != b
  defp kernel_call(:>, [a, b]), do: a > b
  defp kernel_call(:<, [a, b]), do: a < b
  defp kernel_call(:>=, [a, b]), do: a >= b
  defp kernel_call(:<=, [a, b]), do: a <= b
  defp kernel_call(:<>, [a, b]) when is_binary(a) and is_binary(b), do: a <> b
  defp kernel_call(:<>, _), do: reject("<> requires strings")
  defp kernel_call(:not, [a]), do: :erlang.not(a)
  defp kernel_call(:and, [a, b]), do: :erlang.and(a, b)
  defp kernel_call(:or, [a, b]), do: :erlang.or(a, b)
  defp kernel_call(:===, [a, b]), do: a === b
  defp kernel_call(:!==, [a, b]), do: a !== b
  defp kernel_call(:!, [a]), do: not truthy?(a)
  defp kernel_call(:in, [a, b]) when is_list(b), do: Enum.member?(b, a)
  defp kernel_call(:in, _), do: reject("in requires a list")
  defp kernel_call(:to_string, [a]), do: to_string(a)
  defp kernel_call(:is_number, [a]), do: is_number(a)
  defp kernel_call(:is_binary, [a]), do: is_binary(a)
  defp kernel_call(:is_integer, [a]), do: is_integer(a)
  defp kernel_call(:is_nil, [a]), do: is_nil(a)
  defp kernel_call(:max, [a, b]), do: max(a, b)
  defp kernel_call(:min, [a, b]), do: min(a, b)
  defp kernel_call(:then, [value, fun]) when is_function(fun, 1), do: fun.(value)
  defp kernel_call(:then, _), do: reject("then requires a function")
  defp kernel_call(:.., [a, b]), do: Range.new(a, b)
  defp kernel_call(:hd, [a]) when is_list(a) and a != [], do: hd(a)
  defp kernel_call(:hd, _), do: reject("hd requires a non-empty list")
  defp kernel_call(:is_map, [a]), do: is_map(a)
  defp kernel_call(op, args), do: reject("#{op}/#{length(args)}")

  # -- anonymous-function closures ------------------------------------------

  defp build_closure(params, body, bindings) do
    names =
      Enum.map(params, fn
        {name, _, nil} when is_atom(name) -> name
        _ -> reject("unsupported fn parameter")
      end)

    make_fun(names, body, bindings)
  end

  defp make_fun([p1], body, bindings),
    do: fn a1 -> eval_node(body, Map.put(bindings, p1, a1)) end

  defp make_fun([p1, p2], body, bindings),
    do: fn a1, a2 -> eval_node(body, bindings |> Map.put(p1, a1) |> Map.put(p2, a2)) end

  defp make_fun(_params, _body, _bindings), do: reject("unsupported fn arity")

  defp max_placeholder({:&, _, [n]}, acc) when is_integer(n), do: max(n, acc)

  defp max_placeholder({_, _, args}, acc) when is_list(args),
    do: Enum.reduce(args, acc, &max_placeholder/2)

  defp max_placeholder(list, acc) when is_list(list),
    do: Enum.reduce(list, acc, &max_placeholder/2)

  defp max_placeholder({a, b}, acc), do: max_placeholder(b, max_placeholder(a, acc))
  defp max_placeholder(_other, acc), do: acc

  defp make_capture(1, inner, bindings),
    do: fn a1 -> eval_node(inner, Map.put(bindings, {:capture, 1}, a1)) end

  defp make_capture(2, inner, bindings),
    do: fn a1, a2 ->
      eval_node(inner, bindings |> Map.put({:capture, 1}, a1) |> Map.put({:capture, 2}, a2))
    end

  defp make_capture(_arity, _inner, _bindings), do: reject("unsupported capture")

  defp sigil_value(:sigil_T, s), do: Time.from_iso8601!(s)
  defp sigil_value(:sigil_D, s), do: Date.from_iso8601!(s)
  defp sigil_value(:sigil_N, s), do: NaiveDateTime.from_iso8601!(s)

  defp eval_key(k, _bindings) when is_atom(k), do: k
  defp eval_key(k, bindings), do: eval_node(k, bindings)

  # -- control-flow helpers -------------------------------------------------

  defp truthy?(false), do: false
  defp truthy?(nil), do: false
  defp truthy?(_), do: true

  defp eval_cond([], _bindings), do: reject("no cond clause matched")

  defp eval_cond([{:->, _, [[condition], body]} | rest], bindings) do
    if truthy?(eval_node(condition, bindings)),
      do: eval_node(body, bindings),
      else: eval_cond(rest, bindings)
  end

  defp eval_cond([other | _], _bindings), do: reject("disallowed cond clause #{safe_desc(other)}")

  defp inject_pipe(left, {call, meta, args}) when is_list(args), do: {call, meta, [left | args]}
  defp inject_pipe(left, {call, meta, nil}), do: {call, meta, [left]}

  defp eval_block(stmts, bindings) do
    {value, _binds} =
      Enum.reduce(stmts, {nil, bindings}, fn
        {:=, _, [{var, _, nil}, expr]}, {_last, binds} when is_atom(var) ->
          value = eval_node(expr, binds)
          {value, Map.put(binds, var, value)}

        stmt, {_last, binds} ->
          {eval_node(stmt, binds), binds}
      end)

    value
  end

  defp interp_part(s, _bindings) when is_binary(s), do: s

  defp interp_part({:"::", _, [inner, _]}, bindings),
    do: to_string(eval_node(unwrap_to_string(inner), bindings))

  defp unwrap_to_string({{:., _, [_mod, :to_string]}, _, [expr]}), do: expr
  defp unwrap_to_string(other), do: other

  # An unbound or nil variable evaluates to nil (falsy), matching flow semantics
  # where a missing @var is empty. This is what makes the common `@x || "default"`
  # idiom work instead of erroring.
  @spec fetch(binding(), atom()) :: any()
  defp fetch(b, name), do: map_get(b, name)

  # bindings arrive with string keys from MessageVarParser, atom keys elsewhere
  defp map_get(m, key) when is_map(m) do
    case Map.fetch(m, key) do
      {:ok, v} -> v
      :error -> Map.get(m, to_string(key))
    end
  end

  @spec reject(String.t()) :: no_return()
  defp reject(why), do: throw({:reject, why})

  defp to_output(%Date{} = d), do: Date.to_string(d)
  defp to_output(v) when is_binary(v), do: v
  defp to_output(v), do: to_string(v)

  @spec safe_desc(Macro.t()) :: String.t()
  defp safe_desc(node) do
    node |> Macro.to_string() |> String.slice(0, 60)
  rescue
    _ -> "unsupported construct"
  end
end
