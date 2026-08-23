defmodule Glific.AI.Tool.Runner do
  @moduledoc """
  The single dispatch choke point for every AI tool call. Nothing else in the agent runtime may
  invoke `tool.run/2` directly — `call/4` is where a model-requested tool call becomes an
  Elixir function call, and every guard the runtime relies on lives here, in this order:

    1. `Glific.AI.Actor.assert!/2` — the current process is acting as `ctx.user`, in
       `ctx.organization_id`, and is not the organisation root. This is the runtime detector
       for `Repo.put_process_state/1` creeping in above the agent loop (see `Glific.AI.Actor`).
       It raises rather than returning an error, on purpose: a drifted actor is not a
       recoverable tool-call failure, it is a broken invariant, and the whole run must stop.
    2. **Allow-list** — `tool_name` is resolved against `skill.tools()`, never dispatched on
       the model's string alone. Models hallucinate tool names; an unlisted name is an error
       returned to the model, not a crash.
    3. **Role check** — `Glific.Users.Roles.highest_rank(ctx.user.roles)` against
       `tool.required_role()`. Uses `Glific.Users.Roles` because nothing under `lib/glific/ai/`
       may reference `GlificWeb`.
    4. **Parameter validation** — `tool.parameters()` compiled and checked the same way
       `ReqLLM.Tool.new/1` would build it, so an invalid model-supplied argument comes back as
       an error the model can read and retry from, instead of crashing the run. Self-repair is
       the point.
    5. **Timeout** — the tool body runs inside a `Task`, bounded so a tool call plus the
       following model call still fit inside the 45s per-step budget (`shutdown_grace_period`
       is 60s, `config/config.exs:113`).
    6. **Result size cap** — `tool.max_result_bytes()`, truncating with an explicit marker so
       an oversized result degrades instead of blowing the context window or the bill.
    7. **Instrumentation** — call count and latency, tagged by tool name and outcome, in the
       style of `Glific.Flows.Webhooks.Core.Instrumentation`.
    8. **Rescue** — anything that still raises is logged with `Glific.log_error/2` and turned
       into a generic, model-safe failure. An exception message can carry SQL, bind
       parameters, or a `%Tesla.Env{}` with a live bearer token — that never reaches the model.
       `Glific.SafeLog.safe_inspect/1` strips a `%Tesla.Env{}`'s middleware chain before it is
       ever formatted into a log line.

  Steps 2 through 4 (and a tool's own `{:error, _}` result, and a timeout) all return
  `{:error, String.t()}` — recoverable, model-visible failures. Only step 1 raises: that
  failure is not something a tool-calling loop can retry its way out of.
  """

  alias Glific.{
    AI.Actor,
    AI.Tool.Context,
    SafeLog,
    Users.Roles
  }

  @default_timeout_ms 15_000
  @metric_count "ai_tool_call_count"
  @metric_latency "ai_tool_call_latency"

  @doc """
  Runs `tool_name` with `args` on behalf of `ctx`, if `skill` lists it and `ctx.user` is
  allowed to call it.

  Returns `{:ok, result}` or `{:error, message}` — `message` is always safe to hand back to the
  model, verbatim, as the tool's result content.
  """
  @spec call(String.t(), map(), Context.t(), module()) :: {:ok, term()} | {:error, String.t()}
  def call(tool_name, args, %Context{} = ctx, skill)
      when is_binary(tool_name) and is_map(args) and is_atom(skill) do
    Actor.assert!(ctx.organization_id, ctx.user.id)
    dispatch(tool_name, args, ctx, skill)
  end

  @spec dispatch(String.t(), map(), Context.t(), module()) :: {:ok, term()} | {:error, String.t()}
  defp dispatch(tool_name, args, ctx, skill) do
    # `start` is bound here, ahead of the `try`, on purpose: a variable bound inside a `try`
    # body is not visible in its `rescue` clause, and every branch below needs `start` to
    # record latency, including the rescue.
    start = System.monotonic_time()

    try do
      with {:ok, tool} <- fetch_allowed(tool_name, skill),
           :ok <- authorize(tool, ctx.user),
           :ok <- validate_params(tool, args) do
        {result, reason} = run_within_budget(tool, args, ctx)
        track(tool_name, result, reason, start)
        result
      else
        {:error, {reason, message}} ->
          track(tool_name, {:error, message}, reason, start)
          {:error, message}
      end
    rescue
      exception ->
        track(tool_name, {:error, "internal"}, "exception", start)

        Glific.log_error(
          "Glific.AI.Tool.Runner: #{tool_name} raised #{SafeLog.safe_inspect(exception)}"
        )

        {:error, "The tool failed to run. Try a different approach."}
    end
  end

  @spec fetch_allowed(String.t(), module()) ::
          {:ok, module()} | {:error, {String.t(), String.t()}}
  defp fetch_allowed(tool_name, skill) do
    case Enum.find(skill.tools(), &(&1.name() == tool_name)) do
      nil -> {:error, {"unknown_tool", "Unknown tool: #{tool_name}"}}
      tool -> {:ok, tool}
    end
  end

  @spec authorize(module(), Glific.Users.User.t()) :: :ok | {:error, {String.t(), String.t()}}
  defp authorize(tool, user) do
    if Roles.highest_rank(user.roles) >= Roles.rank(tool.required_role()) do
      :ok
    else
      {:error, {"unauthorized", "You do not have permission to use this tool."}}
    end
  end

  @spec validate_params(module(), map()) :: :ok | {:error, {String.t(), String.t()}}
  defp validate_params(tool, args) do
    case build_req_tool(tool) do
      {:ok, req_tool} ->
        case ReqLLM.Tool.validate_input(req_tool, args) do
          {:ok, _validated} ->
            :ok

          {:error, error} ->
            {:error, {"invalid_params", "Invalid arguments: #{format_validation_error(error)}"}}
        end

      {:error, reason} ->
        Glific.log_error(
          "Glific.AI.Tool.Runner: #{tool.name()} has an invalid parameter schema: " <>
            SafeLog.safe_inspect(reason)
        )

        {:error, {"exception", "This tool is temporarily unavailable."}}
    end
  end

  @spec build_req_tool(module()) :: {:ok, ReqLLM.Tool.t()} | {:error, term()}
  defp build_req_tool(tool) do
    ReqLLM.Tool.new(
      name: tool.name(),
      description: tool.description(),
      parameter_schema: tool.parameters(),
      callback: fn _args -> {:ok, nil} end
    )
  end

  # ReqLLM's parameter validation always fails with an exception struct. A future version that
  # returned something else would raise here and be caught by dispatch/4's rescue, which is the
  # real backstop — a hand-rolled non-exception branch is dead code dialyzer can prove.
  @spec format_validation_error(Exception.t()) :: String.t()
  defp format_validation_error(error), do: Exception.message(error)

  # Runs `tool.run/2` inside a Task bounded by `tool_timeout_ms/0`, so a hung tool cannot hang
  # the step. `safe_run/3` never lets the task itself raise, so a timeout here means the tool
  # genuinely did not answer in time — not that it crashed (that is classified separately).
  @spec run_within_budget(module(), map(), Context.t()) ::
          {{:ok, term()} | {:error, String.t()}, String.t()}
  defp run_within_budget(tool, args, ctx) do
    task = Task.async(fn -> safe_run(tool, args, ctx) end)

    case Task.yield(task, tool_timeout_ms()) || Task.shutdown(task, :brutal_kill) do
      {:ok, {reason, result}} -> {result, reason}
      _timed_out_or_killed -> {{:error, "The tool timed out. Try a narrower request."}, "timeout"}
    end
  end

  @spec safe_run(module(), map(), Context.t()) ::
          {String.t(), {:ok, term()} | {:error, String.t()}}
  defp safe_run(tool, args, ctx) do
    case tool.run(args, ctx) do
      {:ok, result} ->
        {"ok", {:ok, cap_result(result, tool.max_result_bytes())}}

      {:error, reason} = error when is_binary(reason) ->
        {"tool_error", error}

      other ->
        Glific.log_error(
          "Glific.AI.Tool.Runner: #{tool.name()} returned an invalid result shape: " <>
            SafeLog.safe_inspect(other)
        )

        {"exception", {:error, "The tool returned an unexpected result."}}
    end
  rescue
    exception ->
      Glific.log_error(
        "Glific.AI.Tool.Runner: #{tool.name()} raised #{SafeLog.safe_inspect(exception)}"
      )

      {"exception", {:error, "The tool failed to run. Try a different approach."}}
  end

  @spec tool_timeout_ms() :: pos_integer()
  defp tool_timeout_ms do
    :glific
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:timeout_ms, @default_timeout_ms)
  end

  @spec cap_result(term(), pos_integer()) :: term()
  defp cap_result(result, max_bytes) do
    encoded = Jason.encode!(result)

    if byte_size(encoded) <= max_bytes do
      result
    else
      truncate(result, max_bytes)
    end
  end

  @spec truncate(term(), pos_integer()) :: term()
  defp truncate(result, max_bytes) when is_list(result) do
    total = length(result)
    kept_count = largest_fitting_prefix(result, total, max_bytes)
    dropped = total - kept_count

    if dropped == 0 do
      Enum.take(result, kept_count)
    else
      Enum.take(result, kept_count) ++ [truncation_marker(dropped)]
    end
  end

  defp truncate(result, max_bytes) do
    marker = " [truncated]"
    encoded = Jason.encode!(result)
    budget = max_bytes |> Kernel.-(byte_size(marker)) |> max(0) |> min(byte_size(encoded))

    encoded
    |> binary_part(0, budget)
    |> valid_utf8_prefix()
    |> Kernel.<>(marker)
  end

  # Recomputes the real marker at every candidate length, rather than reserving a fixed budget
  # for it, so the returned prefix is guaranteed to fit under `max_bytes` exactly — not off by
  # the digit count of `dropped`.
  @spec largest_fitting_prefix([term()], non_neg_integer(), pos_integer()) :: non_neg_integer()
  defp largest_fitting_prefix(list, total, max_bytes) do
    Enum.reduce_while(total..0//-1, 0, fn count, _acc ->
      dropped = total - count
      kept = Enum.take(list, count)
      candidate = if dropped == 0, do: kept, else: kept ++ [truncation_marker(dropped)]

      if byte_size(Jason.encode!(candidate)) <= max_bytes do
        {:halt, count}
      else
        {:cont, 0}
      end
    end)
  end

  @spec truncation_marker(pos_integer()) :: String.t()
  defp truncation_marker(dropped), do: "[truncated: #{dropped} more rows]"

  @spec valid_utf8_prefix(binary()) :: binary()
  defp valid_utf8_prefix(<<>>), do: <<>>

  defp valid_utf8_prefix(binary) do
    if String.valid?(binary),
      do: binary,
      else: valid_utf8_prefix(binary_part(binary, 0, byte_size(binary) - 1))
  end

  @spec track(String.t(), {:ok, term()} | {:error, term()}, String.t(), integer()) :: :ok
  defp track(tool_name, {:ok, _}, reason, start), do: emit(tool_name, "success", reason, start)
  defp track(tool_name, {:error, _}, reason, start), do: emit(tool_name, "error", reason, start)

  @spec emit(String.t(), String.t(), String.t(), integer()) :: :ok
  defp emit(tool_name, outcome, reason, start) do
    tags = %{tool_name: tool_name, outcome: outcome, reason: reason}

    Appsignal.increment_counter(@metric_count, 1, tags)
    Appsignal.add_distribution_value(@metric_latency, duration_ms(start), tags)

    :ok
  end

  @spec duration_ms(integer()) :: non_neg_integer()
  defp duration_ms(start_monotonic) do
    System.monotonic_time()
    |> Kernel.-(start_monotonic)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
