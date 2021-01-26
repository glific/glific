defmodule Glific.Sandbox do
  @moduledoc """

  #### --- Warning ---
  #### This code has been copied from: https://github.com/DarkMarmot/elixir_sandbox/
  #### It has not been updated for more than 16 months and hence pulling it into the
  #### glific repository. We will document all changes we make

  #### This library is under heavy development and will have breaking changes until the 1.0.0 release.

  Sandbox provides restricted, isolated scripting environments for Elixir through the use of embedded Lua.

  This project is powered by Robert Virding's amazing [Luerl](https://github.com/rvirding/luerl), an Erlang library that lets one execute Lua scripts on the BEAM.

  Luerl executes Lua code _without_ running a Lua VM as a separate application! Rather, the state of the VM is used as a
  data structure that can be externally manipulated and processed.

  The `:luerl_sandbox` module is utilized wherever possible. This limits access to dangerous core libraries.
  It also permits Lua scripts to be run with enforced CPU reduction limits. To work with Lua's full library, use
  `Sandbox.unsafe_init/0` as opposed to `Sandbox.init/0`.

  Conventions followed in this library:

  - Functions beginning with `eval` return a result from Lua.
  - Functions starting with `play` return a new Lua state.
  - Functions preceded by `run` return a tuple of `{result, new_state}`
  - All functions return ok-error tuples such as `{:ok, value}` or `{:error, reason}` unless followed by a bang.
  - Elixir functions exposed to Lua take two arguments: a Lua state and a list of Lua arguments. They
    should return a value corresponding to the `eval`, `play` or `run` responses.
  - The `max_reductions` argument defaults to `0`, corresponding to unlimited reductions.

  """
  @unlimited_reductions 0
  @sandbox_error "Lua Sandbox Error: "
  @reduction_error @sandbox_error <> "exceeded reduction limit!"

  @typedoc """
  Compiled Lua code that can be transferred between Lua states.
  """
  @type lua_chunk :: {:lua_func, any(), any(), any(), any(), any()}
  @typedoc """
  The representation of an entire Lua virtual machine and its current state.
  """
  @type lua_state ::
          {:luerl, any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any(),
           any(), any(), any()}
  @typedoc """
  Lua code as either a raw string or compile chunk.
  """
  @type lua_code :: lua_chunk() | String.t()
  @typedoc """
  Lua values represented as Elixir data structures.
  """
  @type lua_value :: number() | String.t() | [tuple()] | nil
  @typedoc """
  A dot-delimited name or list of names representing a table path in Lua such as `math.floor` or `["math", "floor"]`.
  """
  @type lua_path :: String.t() | [String.t()]
  @typedoc """
  An Elixir function that can be invoked through Lua. It takes a Lua state and a list of Lua arguments and returns
  a tuple containing a result and a new Lua state.
  """
  @type elixir_run_fun :: (lua_state(), [lua_value()] -> {any(), lua_state()})
  @typedoc """
  An Elixir function that can be invoked through Lua. It takes a Lua state and a list of Lua arguments and returns
  a result. The Lua state acts as a context but is not modified.
  """
  @type elixir_eval_fun :: (lua_state(), [lua_value()] -> any())
  @typedoc """
  An Elixir function that can be invoked through Lua. It takes a Lua state and a list of Lua arguments and returns
  a new Lua state. The result of this function is not exposed to Lua.
  """
  @type elixir_play_fun :: (lua_state(), [lua_value()] -> lua_state())

  @doc """
  Creates a Lua state with "dangerous" core library features such as file IO and networking removed.
  """
  def init() do
    :luerl_sandbox.init()
  end

  @doc """
  Creates a Lua state with access to Lua's standard library. The `max_reductions` feature of `Sandbox` is still
  available, but "dangerous" core library features such as file IO and networking are still available.
  """
  def unsafe_init() do
    :luerl.init()
  end

  @doc ~S"""
  Evaluates a Lua string or chunk against the given Lua state and returns the result in an ok-error tuple. The state itself is not modified.

  ## Examples

      iex> Sandbox.init() |> Sandbox.eval("return 3 + 4")
      {:ok, 7.0}

      iex> Sandbox.init() |> Sandbox.eval("return math.floor(9.9)")
      {:ok, 9.0}

  """
  @spec eval(lua_state(), lua_code(), non_neg_integer()) :: {:ok, lua_value()} | {:error, any()}
  def eval(state, code, max_reductions \\ @unlimited_reductions) do
    case :luerl_sandbox.run(code, state, max_reductions) do
      {:error, e} -> {:error, e}
      {[{:tref, _} = table | _], new_state} -> {:ok, :luerl.decode(table, new_state)}
      {[result | _], _new_state} -> {:ok, result}
      {[], _} -> {:ok, nil}
    end
  end

  @doc ~S"""
  Same as `eval/3`, but will return the raw result or raise a `RuntimeError`.

  ## Examples

      iex> Sandbox.init() |> Sandbox.eval!("return 3 + 4")
      7.0

      iex> Sandbox.init() |> Sandbox.eval!("return math.floor(9.9)")
      9.0

  """
  @spec eval!(lua_state(), lua_code(), non_neg_integer()) :: lua_value()
  def eval!(state, code, max_reductions \\ @unlimited_reductions) do
    case :luerl_sandbox.run(code, state, max_reductions) do
      {:error, {:reductions, _n}} -> raise(@reduction_error)
      {:error, reason} -> raise(@sandbox_error <> "#{inspect(reason)}")
      {[{:tref, _} = table | _], new_state} -> :luerl.decode(table, new_state)
      {[result | _], _new_state} -> result
      {[], _new_state} -> nil
    end
  end

  @doc """
  Evaluates a Lua file against the given Lua state and returns the result in an ok-error tuple. The state itself is not modified.
  """

  @spec eval_file(lua_state(), String.t(), non_neg_integer()) ::
          {:ok, lua_value()} | {:error, any()}
  def eval_file(state, file_path, max_reductions \\ @unlimited_reductions) do
    with {:ok, code} <- File.read(file_path),
         {:ok, result} <- eval(state, code, max_reductions) do
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Same as `eval_file/3`, but will return the raw result or raise a `RuntimeError`.
  """

  @spec eval_file!(lua_state(), String.t(), non_neg_integer()) :: lua_value()
  def eval_file!(state, file_path, max_reductions \\ @unlimited_reductions) do
    code = File.read!(file_path)
    eval!(state, code, max_reductions)
  end

  @doc """
  Calls a function defined in the the Lua state and returns only the result. The state itself is not modified.
  Lua functions in the Lua state can be referenced by their `lua_path`, being a string or list such as `math.floor` or `["math", "floor"]`.
  """

  @spec eval_function!(lua_state(), lua_path(), non_neg_integer()) :: lua_value()
  def eval_function!(state, path, args \\ [], max_reductions \\ @unlimited_reductions)

  def eval_function!(state, path, args, max_reductions) when is_list(path) do
    eval_function!(state, Enum.join(path, "."), args_to_list(args), max_reductions)
  end

  def eval_function!(state, path, args, max_reductions) when is_binary(path) do
    state
    |> set!("__sandbox_args__", args_to_list(args))
    |> eval!("return " <> path <> "(unpack(__sandbox_args__))", max_reductions)
  end

  @doc """
  Create a compiled chunk of Lua code that can be transferred between Lua states, returned in an ok-error tuple.
  """
  @spec chunk(lua_state(), lua_code()) :: {:ok, lua_chunk()} | {:error, any()}
  def chunk(state, code) do
    case :luerl.load(code, state) do
      {:ok, result, _state} ->
        {:ok, result}

      {:error, e1, e2} ->
        {:error, {e1, e2}}
        #      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Same as `chunk/2`, but will return the raw result or raise a `RuntimeError`.
  """

  @spec chunk!(lua_state(), lua_code()) :: lua_chunk()
  def chunk!(state, code) do
    {:ok, result} = chunk(state, code)
    result
  end

  @doc """
  Runs a Lua string or chunk against a Lua state and returns a new Lua state in an ok-error tuple.
  """
  @spec play(lua_state(), lua_code(), non_neg_integer()) :: {:ok, lua_state()} | {:error, any()}
  def play(state, code, max_reductions \\ @unlimited_reductions) do
    case :luerl_sandbox.run(code, state, max_reductions) do
      {:error, e} -> {:error, e}
      {_result, new_state} -> {:ok, new_state}
    end
  end

  @doc """
  Same as `play/3`, but will return the raw result or raise a `RuntimeError`.
  """
  @spec play!(lua_state(), lua_code(), non_neg_integer()) :: lua_state()
  def play!(state, code, max_reductions \\ @unlimited_reductions) do
    case :luerl_sandbox.run(code, state, max_reductions) do
      {:error, {:reductions, _n}} -> raise(@reduction_error)
      {_result, new_state} -> new_state
    end
  end

  @doc """
  Runs a Lua file in the context of a Lua state and returns a new Lua state.
  """
  @spec play_file!(lua_state(), String.t(), non_neg_integer()) :: lua_state()
  def play_file!(state, file_path, max_reductions \\ @unlimited_reductions)
      when is_binary(file_path) and is_integer(max_reductions) do
    code = File.read!(file_path)
    play!(state, code, max_reductions)
  end

  @doc """
  Runs a Lua function defined in the given Lua state and returns a new Lua state.
  """
  @spec play_function!(lua_state(), lua_path(), non_neg_integer()) :: lua_state()
  def play_function!(state, path, args \\ [], max_reductions \\ @unlimited_reductions)

  def play_function!(state, path, args, max_reductions) when is_list(path) do
    play_function!(state, Enum.join(path, "."), args_to_list(args), max_reductions)
  end

  def play_function!(state, path, args, max_reductions) when is_binary(path) do
    state
    |> set!("__sandbox_args__", args_to_list(args))
    |> play!("return " <> path <> "(unpack(__sandbox_args__))", max_reductions)
  end

  @doc """
  Runs a Lua string or chunk against the given Lua state and returns the result and the new Lua state in an ok-error tuple.
  """

  @spec run(lua_state(), lua_code(), non_neg_integer()) ::
          {:ok, lua_state() | {lua_value(), lua_state()}} | {:error, any()}
  def run(state, code, max_reductions \\ @unlimited_reductions) do
    case :luerl_sandbox.run(code, state, max_reductions) do
      {:error, e} -> {:error, e}
      {[], new_state} -> {:ok, {nil, new_state}}
      {[{:tref, _} = table | _], new_state} -> {:ok, {:luerl.decode(table, new_state), new_state}}
      {[result | _], new_state} -> {:ok, {result, new_state}}
    end
  end

  @doc """
  Same as `run/3`, but will return the raw `{result, state}` or raise a `RuntimeError`.
  """
  @spec run!(lua_state(), lua_code(), non_neg_integer()) :: {lua_value(), lua_state()}
  def run!(state, code, max_reductions \\ @unlimited_reductions) do
    case :luerl_sandbox.run(code, state, max_reductions) do
      {:error, {:reductions, _n}} -> raise(@reduction_error)
      {[{:tref, _} = table], new_state} -> {:luerl.decode(table, new_state), new_state}
      {[result], new_state} -> {result, new_state}
      {[], new_state} -> {nil, new_state}
    end
  end

  @doc """
  Runs a function defined in the the Lua state and returns the result and the new Lua state as `{result, state}`.
  Lua functions in the Lua state can be referenced by their `lua_path`, a string or list such as `math.floor` or `["math", "floor"]`.
  """

  @spec run_function!(lua_state(), lua_path(), non_neg_integer()) :: {lua_value(), lua_state()}
  def run_function!(state, path, args \\ [], max_reductions \\ @unlimited_reductions)

  def run_function!(state, path, args, max_reductions) when is_list(path) do
    run_function!(state, Enum.join(path, "."), args_to_list(args), max_reductions)
  end

  def run_function!(state, path, args, max_reductions) when is_binary(path) do
    state
    |> set!("__sandbox_args__", args_to_list(args))
    |> run!("return " <> path <> "(unpack(__sandbox_args__))", max_reductions)
  end

  @doc """
  Sets a value in a Lua state and returns the modified state. If `force` is set to true, new tables will be created
  automatically if they missing from the given `lua_path`.
  """
  @spec set!(lua_state(), lua_path(), any(), boolean()) :: lua_state()
  def set!(state, path, value, force \\ false)

  def set!(state, path, value, force) when is_binary(path) do
    set!(state, String.split(path, "."), value, force)
  end

  def set!(state, path, value, false) when is_list(path) do
    :luerl.set_table(path, value, state)
  end

  def set!(state, path, value, true) when is_list(path) do
    :luerl.set_table(path, value, build_missing_tables(state, path))
  end

  @doc """
  Gets a value from a Lua state.
  """
  @spec get!(lua_state(), lua_path()) :: lua_value()
  def get!(state, path) when is_list(path) do
    {result, _s} = :luerl.get_table(path, state)
    result
  end

  def get!(state, path) when is_binary(path) do
    get!(state, String.split(path, "."))
  end

  @doc """
  Returns a Lua state modified to include an Elixir function, `elixir_eval_fun()`, at the given `lua_path()`.

  The `elixir_eval_fun()` takes two arguments, a Lua state and a list of calling arguments from Lua.
  Its return value is passed along to Lua. It will not mutate the Lua state against which it executes.
  """
  @spec let_elixir_eval!(lua_state(), lua_path(), elixir_eval_fun()) ::
          lua_state()
  def let_elixir_eval!(state, name, fun) when is_function(fun) do
    value = lua_wrap_elixir_eval(fun)
    set!(state, name, value)
  end

  @doc """
  Returns a Lua state modified to include an Elixir function, `elixir_play_fun()`, at the given `lua_path()`.

  The `elixir_play_fun()` takes two arguments, a Lua state and a list of calling arguments from Lua.
  It should return a new Lua state.

  This can be used to let Lua scripts use something like controlled inheritance, dynamically adding external functionality and settings.
  """
  @spec let_elixir_play!(lua_state(), lua_path(), elixir_play_fun()) ::
          lua_state()
  def let_elixir_play!(state, path, fun) when is_function(fun) do
    value = lua_wrap_elixir_play(fun)
    set!(state, path, value)
  end

  @doc """
  Returns a Lua state modified to include an Elixir function, `elixir_run_fun()`, at the given `lua_path()`.

  The `elixir_run_fun()` takes two arguments, a Lua state and a list of calling arguments from Lua.
  It should return a tuple holding the result intended for the calling Lua function alongside a new Lua state.
  """
  @spec let_elixir_run!(lua_state(), lua_path(), elixir_run_fun()) ::
          lua_state()
  def let_elixir_run!(state, name, fun) when is_function(fun) do
    value = lua_wrap_elixir_run(fun)
    set!(state, name, value)
  end

  @doc false
  def reduction_error(), do: @reduction_error

  # --- private functions ---

  # lua state is unchanged, result returned
  defp lua_wrap_elixir_eval(fun) do
    fn args, state ->
      result = fun.(state, args)
      {[result], state}
    end
  end

  # lua result and state returned
  defp lua_wrap_elixir_run(fun) do
    fn args, state ->
      {result, new_state} = fun.(state, args)
      {[result], new_state}
    end
  end

  # lua state is changed
  defp lua_wrap_elixir_play(fun) do
    fn args, state ->
      new_state = fun.(state, args)
      {[], new_state}
    end
  end

  defp args_to_list(args) when is_list(args) do
    args
  end

  defp args_to_list(args) do
    [args]
  end

  defp build_missing_tables(state, path, path_string \\ nil)

  defp build_missing_tables(state, [], _path_string) do
    state
  end

  defp build_missing_tables(state, [name | path_remaining], path_string) do
    next_path_string =
      case path_string do
        nil -> name
        _ -> path_string <> "." <> name
      end

    next_state =
      case get!(state, next_path_string) do
        nil -> set!(state, next_path_string, [])
        _ -> state
      end

    build_missing_tables(next_state, path_remaining, next_path_string)
  end
end
