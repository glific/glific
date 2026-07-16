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
  3. **Fail closed.** `e/2` implements only the allowed node types. `alias`,
     `import`, `fn`, captures, computed modules and `apply/3` need no dedicated
     rule — they have no clause and fall to the catch-all, which rejects.
  4. **Modules resolve through `@mfa` only**, never Elixir's alias resolution.
     The module position must be a literal alias on the table.
  5. **Variables are data.** `@foo` reads from a bindings map; a value can never
     become code.

  ## Where the security guarantee lives

  `e/2` (and its catch-all) is the **sole** security boundary. `safe_shape/1` is
  a cheap, deliberately permissive structural pre-check used at publish time for
  early author feedback — it is NOT a gate, and nothing that reaches `e/2` may
  rely on it having run. Do not "optimise" by trusting `safe_shape/1` at runtime.
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
    {:String, :length, 1} => &String.length/1,
    {:String, :upcase, 1} => &String.upcase/1,
    {:String, :downcase, 1} => &String.downcase/1,
    {:String, :trim, 1} => &String.trim/1,
    {:Enum, :count, 1} => &Enum.count/1,
    {:Timex, :today, 0} => &Date.utc_today/0,
    {:Date, :utc_today, 0} => &Date.utc_today/0
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
    {:or, 2}
  ]

  # Resource limits. An interpreter prevents RCE, not resource exhaustion:
  # `2*2*2*...` builds bignums, and Glific runs a single BEAM node shared with
  # Oban and the web server.
  @max_nodes 100
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
        case isolated(fn -> e(ast, bindings) end) do
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

  # Structural validation that mirrors e/2's accepted node shapes exactly by
  # recursing top-down — never classifying a sub-node in isolation. Because it is
  # the structural twin of e/2, `validate/1` cannot green-light anything e/2
  # would reject: the two stay in lock-step and there is no publish-vs-runtime
  # drift. It cannot see runtime-only failures (division by zero, field access on
  # a non-map, unbound variable), which remain e/2's responsibility.
  @spec safe_shape(Macro.t()) :: :ok | {:error, String.t()}
  defp safe_shape(ast), do: validate_ast(ast)

  @spec validate_ast(Macro.t()) :: :ok | {:error, String.t()}
  defp validate_ast(n)
       when is_integer(n) or is_float(n) or is_binary(n) or is_boolean(n) or is_nil(n),
       do: :ok

  defp validate_ast(n) when is_atom(n),
    do: {:error, "bare atom #{Glific.SafeLog.safe_inspect(n)}"}

  defp validate_ast(l) when is_list(l), do: validate_all(l)

  defp validate_ast({:@, _, [{name, _, nil}]}) when is_atom(name), do: :ok

  defp validate_ast({name, _, nil}) when is_atom(name), do: :ok

  # remote call: only literal-alias modules on the @mfa table
  defp validate_ast({{:., _, [{:__aliases__, _, [m]}, f]}, _, args}) when is_list(args) do
    if Map.has_key?(@mfa, {m, f, length(args)}),
      do: validate_all(args),
      else: {:error, "#{m}.#{f}/#{length(args)}"}
  end

  # field access: inner must itself be a valid data expression (a var, @var or a
  # nested field chain) -- never a bare atom or module.
  defp validate_ast({{:., _, [inner, f]}, _, []}) when is_atom(f), do: validate_ast(inner)

  # operators / Kernel calls on the @kernel table
  defp validate_ast({op, _, args}) when is_atom(op) and is_list(args) do
    if {op, length(args)} in @kernel,
      do: validate_all(args),
      else: {:error, "#{op}/#{length(args)}"}
  end

  defp validate_ast(node), do: {:error, "disallowed expression: #{safe_desc(node)}"}

  @spec validate_all([Macro.t()]) :: :ok | {:error, String.t()}
  defp validate_all(nodes) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case validate_ast(node) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  # -- evaluation -----------------------------------------------------------

  # Phase 1 path: content has already been through MessageVarParser, so all
  # @vars are literals and `existing_atoms_only: true` is both safe and lossless.
  @spec eval_expr(String.t(), binding()) :: {:ok, any()} | {:error, String.t()}
  defp eval_expr(src, bindings) do
    with {:ok, ast} <- parse(src, true),
         :ok <- check_size(ast),
         :ok <- safe_shape(ast) do
      isolated(fn -> e(ast, bindings) end)
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
  defp e(n, _)
       when is_integer(n) or is_float(n) or is_binary(n) or is_boolean(n) or is_nil(n),
       do: n

  defp e(n, _) when is_atom(n), do: reject("bare atom #{Glific.SafeLog.safe_inspect(n)}")

  defp e(l, b) when is_list(l), do: Enum.map(l, &e(&1, b))

  # EEx assign: @results -> bindings lookup. Data, never code.
  defp e({:@, _, [{name, _, nil}]}, b) when is_atom(name), do: fetch(b, name)

  # bare var
  defp e({name, _, nil}, b) when is_atom(name), do: fetch(b, name)

  # remote call: module MUST be a literal alias on the table. This is the only
  # path to a module, so alias/import/computed modules cannot reach one.
  defp e({{:., _, [{:__aliases__, _, [m]}, f]}, _, args}, b) when is_list(args) do
    key = {m, f, length(args)}

    case Map.fetch(@mfa, key) do
      {:ok, fun} -> apply(fun, Enum.map(args, &e(&1, b)))
      :error -> reject("#{m}.#{f}/#{length(args)}")
    end
  end

  # field access on plain maps only -- never structs, never modules
  defp e({{:., _, [inner, key]}, _, []}, b) when is_atom(key) do
    case e(inner, b) do
      m when is_map(m) and not is_struct(m) -> map_get(m, key)
      _ -> reject("field access on non-map")
    end
  end

  # allowed operators / Kernel calls
  defp e({op, _, args}, b) when is_atom(op) and is_list(args) do
    if {op, length(args)} in @kernel,
      do: kernel_call(op, Enum.map(args, &e(&1, b))),
      else: reject("#{op}/#{length(args)}")
  end

  # FAIL-CLOSED CATCH-ALL. alias, import, fn, &capture, spawn, apply/3,
  # __block__, sigils, computed modules all land here. No rule needed.
  defp e(node, _), do: reject(safe_desc(node))

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
  defp kernel_call(op, args), do: reject("#{op}/#{length(args)}")

  @spec fetch(binding(), atom()) :: any()
  defp fetch(b, name) do
    case map_get(b, name) do
      nil -> reject("unbound variable @#{name}")
      v -> v
    end
  end

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
