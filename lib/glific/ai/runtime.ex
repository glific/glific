defmodule Glific.AI.Runtime do
  @moduledoc """
  The agent loop's pure decision function: given one step's state, decide what happens next.

  `step/1` is the only function in this module anything outside it needs to call. It makes no
  Oban calls and touches no `Repo` — the only I/O it performs is the model call
  (`Glific.AI.Model.chat/2`, `Glific.AI.Model.object/3`) and running tool calls through
  `Glific.AI.Tool.Runner.call/4`, both of which are already the seams the rest of the runtime
  tests against (`Glific.AI.Model.Stub`, tool fixtures). Everything else — persisting messages,
  scheduling the next job, enforcing the step budget, guarding against a late or duplicate job —
  is `Glific.AI.StepWorker`'s job, not this module's.

  ## What one call to `step/1` does

  It looks at the last message in `state.context`:

    * If it is an assistant message carrying unanswered tool calls, this step is a **tool
      batch**: every call is run through `Glific.AI.Tool.Runner.call/4` and turned into a
      `role: :tool` message.
    * Otherwise, this step is a **model call**: `state.skill.system_prompt/1` (rendered fresh,
      never persisted — Postgres's `ai_message_role_enum` has no `:system` value, only
      `user | assistant | tool`) is prepended to `state.context` and sent to
      `Glific.AI.Model.chat/2`. A `finish_reason: :tool_calls` response persists the assistant's
      tool-call message and continues; any other response is the run's final answer.

  A step never mixes the two — "one job = one model call or one tool batch" is what keeps a
  single Oban job's wall-clock budget predictable.

  ## Deriving `input`

  `Glific.AI.Skill.system_prompt/1` and `build_proposal/2` take a caller-supplied `input` map,
  but nothing in the conversation/message schema persists one. This runtime derives it from the
  conversation's first stored message: `%{"message" => <that message's text>}`, matching
  `Glific.AI.Skills.Echo`'s contract exactly. A skill whose prompt needs a richer structured
  input than a single string is not yet supported by this derivation — extending `input` beyond
  `"message"` needs either a persisted input column or a documented richer convention, and is
  intentionally left for whoever adds the second such skill.

  ## Result

      step(state) ::
          {:continue, state, [message_attrs]}
        | {:suspend, state, proposal, [message_attrs]}
        | {:done, state, result, [message_attrs]}
        | {:transient_error, term()}
        | {:permanent_error, term()}

  `message_attrs` is a **list** (never empty) rather than the single map a step machine usually
  returns, because one model turn can request several tool calls, and every one of them needs
  its own `role: :tool` row — `ReqLLM.Message.tool_call_id` is a single id, not a list, so
  multiple tool results cannot be folded into one row. `Glific.AI.StepWorker` assigns `seq` to
  each entry in order and persists them in one `Ecto.Multi`.

  Every map in `message_attrs` is ready for `Glific.AI.append_message/2` except `seq`
  (assigned by the caller, which is the only one who knows the run's current message count) and
  `conversation_id`/`organization_id` (filled in by `append_message/2` itself).

  A `:transient_error` covers every `Glific.AI.Model` failure — network errors, timeouts, 429s,
  5xxs — indiscriminately: `Glific.AI.Model.ReqLLM` already collapses the provider's structured
  error into a logged string (see its `call_failed/2`), so this runtime cannot reliably tell a
  retryable failure from a permanent one by inspecting the reason term, and treats them all as
  retryable. Oban's `max_attempts: 3` bounds how long a genuinely permanent failure (e.g. a bad
  API key) gets retried before it lands in `discarded`.

  A `:permanent_error` is reserved for failures that are not the model's or a tool's to retry:
  `Glific.AI.Codec.encode/1` refusing to serialise a message (a programming bug, not a bad
  response), a skill's `build_proposal/2` returning `{:error, _}` (a skill contract violation),
  and `Glific.AI.Actor.Error` raised by `Glific.AI.Tool.Runner.call/4` when the acting identity
  has drifted — see `Glific.AI.Tool.Runner`'s own moduledoc: that failure "is not something a
  tool-calling loop can retry its way out of."

  ## Resuming after a gate: `resume/2`

  `resume/2` is `step/1`'s sibling for the other half of the propose→confirm gate: once a human
  has accepted or rejected the proposal `state.skill.build_proposal/2` produced, `resume/2`
  calls `state.skill.on_decision/3` and maps its result onto the same shape `step/1` returns —
  `{:continue, state, message_attrs}` or `{:done, state, result, message_attrs}` — so
  `Glific.AI.StepWorker` does not need a second persistence path. `resume/2` never suspends
  again; `on_decision/3` is a one-shot resolution of the gate, not a new one.

  **The decision is always persisted as its own message, synthesized by this module — not left
  to the skill.** `resume/2` builds a deterministic `role: :user` message ("The proposal was
  accepted."/"The proposal was rejected.", constant text, no interpolation) and puts it first in
  `message_attrs`, ahead of anything `on_decision/3` itself returns via `{:continue, messages}`.
  Two reasons: first, a skill that continues the run needs a transcript where a later turn's
  context makes sense regardless of whether that skill's author remembered to record the
  decision itself — this runtime guarantees it rather than trusting every skill to. Second, a
  `{:done, payload}` skill has no `{:continue, messages}` of its own to record anything in, so
  synthesizing here is the only way a `:done` resume ever leaves a trace of what was decided in
  the transcript at all. The synthesized text is a constant precisely for the reason
  `Glific.AI.Skill`'s moduledoc gives for prompts: anything interpolated (a timestamp, the raw
  proposal) would defeat provider prompt caching on every later step with no functional symptom
  to point at the cause.

  `on_decision/3` is an `@optional_callback` — a skill whose `gate_policy/0` is
  `{:on_final, _}` but that does not implement it is a contract violation, exactly like a
  `build_proposal/2` that returns `{:error, _}`, and `resume/2` reports it the same way:
  `{:permanent_error, {:on_decision_not_implemented, skill}}`. Checked here rather than earlier
  (e.g. at suspend time) because a skill's callbacks are enumerable at any point via
  `function_exported?/3` and gate resolution — not gate suspension — is the first moment this
  runtime actually needs to call it; catching it earlier would mean checking every gated skill
  on every suspend for a defect only resume ever exercises. A raised exception from
  `on_decision/3` itself, or a return shape that is neither `{:done, _}` nor `{:continue, list}`,
  is reported the same way: a skill's callback misbehaving is a bug in that skill, not a
  retryable runtime condition.
  """

  alias Glific.AI.Codec
  alias Glific.AI.Model
  alias Glific.AI.Model.Result
  alias Glific.AI.Runtime.State
  alias Glific.AI.Skill
  alias Glific.AI.Tool
  alias Glific.AI.Tool.Runner
  alias ReqLLM.Context
  alias ReqLLM.Message
  alias ReqLLM.ToolCall

  @structured_output_request "Now return that answer in the required structured format."

  @typedoc "One entry ready for `Glific.AI.append_message/2`, minus `seq`."
  @type message_attrs :: map()

  @type result ::
          {:continue, State.t(), [message_attrs()]}
          | {:suspend, State.t(), map(), [message_attrs()]}
          | {:done, State.t(), term(), [message_attrs()]}
          | {:transient_error, term()}
          | {:permanent_error, term()}

  @doc "Advances a run by exactly one model call or one tool batch."
  @spec step(State.t()) :: result()
  def step(%State{context: %Context{messages: messages}} = state) do
    case List.last(messages) do
      %Message{role: :assistant, tool_calls: [_ | _] = tool_calls} ->
        run_tool_batch(state, tool_calls)

      _no_pending_tool_calls ->
        run_model_call(state)
    end
  end

  @doc """
  Resumes a run whose skill suspended it awaiting a human decision. See the moduledoc's
  "Resuming after a gate" section for what gets persisted and why.
  """
  @spec resume(State.t(), :accepted | :rejected) :: result()
  def resume(%State{skill: skill} = state, decision) do
    if function_exported?(skill, :on_decision, 3) do
      dispatch_decision(state, decision)
    else
      {:permanent_error, {:on_decision_not_implemented, skill}}
    end
  rescue
    error -> {:permanent_error, error}
  end

  @spec dispatch_decision(State.t(), :accepted | :rejected) :: result()
  defp dispatch_decision(%State{skill: skill, conversation: conversation} = state, decision) do
    case decision_message_attrs(state, decision) do
      {:ok, decision_attrs} ->
        decision
        |> skill.on_decision(conversation, conversation.pending_proposal)
        |> handle_decision_result(state, decision_attrs)

      {:error, reason} ->
        {:permanent_error, reason}
    end
  end

  @spec handle_decision_result(term(), State.t(), message_attrs()) :: result()
  defp handle_decision_result({:done, payload}, state, decision_attrs),
    do: {:done, advance(state), payload, [decision_attrs]}

  defp handle_decision_result({:continue, messages}, state, decision_attrs)
       when is_list(messages) do
    case continuation_message_attrs(state, messages) do
      {:ok, attrs} -> {:continue, advance(state), [decision_attrs | attrs]}
      {:error, reason} -> {:permanent_error, reason}
    end
  end

  defp handle_decision_result(other, _state, _decision_attrs),
    do: {:permanent_error, {:invalid_on_decision_result, other}}

  @spec decision_message_attrs(State.t(), :accepted | :rejected) ::
          {:ok, message_attrs()} | {:error, term()}
  defp decision_message_attrs(%State{conversation: conversation}, decision) do
    decision
    |> decision_text()
    |> Context.user()
    |> build_message_attrs(request_id: conversation.active_request_id)
  end

  @spec decision_text(:accepted | :rejected) :: String.t()
  defp decision_text(:accepted), do: "The proposal was accepted."
  defp decision_text(:rejected), do: "The proposal was rejected."

  @spec continuation_message_attrs(State.t(), [Message.t()]) ::
          {:ok, [message_attrs()]} | {:error, term()}
  defp continuation_message_attrs(%State{conversation: conversation}, messages) do
    Enum.reduce_while(messages, {:ok, []}, fn message, {:ok, acc} ->
      case build_message_attrs(message, request_id: conversation.active_request_id) do
        {:ok, attrs} -> {:cont, {:ok, [attrs | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, attrs} -> {:ok, Enum.reverse(attrs)}
      {:error, _reason} = error -> error
    end
  end

  @spec run_model_call(State.t()) :: result()
  defp run_model_call(%State{} = state) do
    request_context = build_request_context(state)
    start = System.monotonic_time()

    case Model.chat(request_context, model_opts(state)) do
      {:ok, %Result{finish_reason: :tool_calls} = result} ->
        continue_with_assistant_message(state, result, start)

      {:ok, %Result{} = result} ->
        finalize(state, result, start)

      {:error, reason} ->
        {:transient_error, reason}
    end
  end

  @spec build_request_context(State.t()) :: Context.t()
  defp build_request_context(%State{context: context} = state) do
    prompt = state.skill.system_prompt(derive_input(context))
    Context.prepend(context, Context.system(prompt))
  end

  @spec continue_with_assistant_message(State.t(), Result.t(), integer()) :: result()
  defp continue_with_assistant_message(%State{} = state, %Result{} = result, start) do
    case assistant_message_attrs(state, result, start) do
      {:ok, attrs} -> {:continue, advance(state), [attrs]}
      {:error, reason} -> {:permanent_error, reason}
    end
  end

  @spec finalize(State.t(), Result.t(), integer()) :: result()
  defp finalize(%State{} = state, %Result{} = result, start) do
    case assistant_message_attrs(state, result, start) do
      {:ok, attrs} -> complete_or_suspend(state, result, attrs)
      {:error, reason} -> {:permanent_error, reason}
    end
  end

  @spec complete_or_suspend(State.t(), Result.t(), message_attrs()) :: result()
  defp complete_or_suspend(%State{} = state, %Result{} = result, assistant_attrs) do
    case state.skill.output_schema() do
      nil -> gate_or_done(state, result.message, assistant_attrs)
      schema -> validate_output(state, result, schema, assistant_attrs)
    end
  end

  # `result.context` ends with the assistant's own reply, and Anthropic's generate_object
  # rejects a context in that shape outright ("does not support contexts ending with an
  # assistant message"). Appending this turn is the provider's own prescribed fix, and it keeps
  # the drafted answer in context so the structuring pass formats what the model already wrote
  # rather than redoing the work from scratch. The text is a constant for the usual reason:
  # anything interpolated here would be a cache-prefix mismatch on every call.
  #
  # Tools are dropped for this pass — a structured-output call has no business emitting tool
  # calls, and offering them invites a response this branch cannot handle.
  @spec validate_output(State.t(), Result.t(), Skill.output_schema(), message_attrs()) ::
          result()
  defp validate_output(%State{} = state, %Result{context: context}, schema, assistant_attrs) do
    object_opts = Keyword.delete(model_opts(state), :tools)

    context
    |> Context.append(Context.user(@structured_output_request))
    |> Model.object(schema, object_opts)
    |> case do
      {:ok, object} -> gate_or_done(state, object, assistant_attrs)
      {:error, reason} -> {:transient_error, reason}
    end
  end

  @spec gate_or_done(State.t(), term(), message_attrs()) :: result()
  defp gate_or_done(%State{} = state, output, assistant_attrs) do
    case state.skill.gate_policy() do
      :none ->
        {:done, advance(state), output, [assistant_attrs]}

      {:on_final, _ttl_seconds} ->
        case state.skill.build_proposal(output, derive_input(state.context)) do
          {:ok, proposal} -> {:suspend, advance(state), proposal, [assistant_attrs]}
          {:error, reason} -> {:permanent_error, reason}
        end
    end
  end

  @spec run_tool_batch(State.t(), [ToolCall.t()]) :: result()
  defp run_tool_batch(%State{} = state, tool_calls) do
    tool_context = %Tool.Context{
      organization_id: state.organization_id,
      user: state.user,
      request_id: state.conversation.active_request_id,
      step_index: state.step_index
    }

    tool_calls
    |> Enum.reduce_while({:ok, []}, fn call, {:ok, acc} ->
      case run_tool_call(call, tool_context, state.skill) do
        {:ok, attrs} -> {:cont, {:ok, [attrs | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, attrs} -> {:continue, advance(state), Enum.reverse(attrs)}
      {:error, reason} -> {:permanent_error, reason}
    end
  rescue
    # Actor.assert!/2 raises rather than returns on a drifted acting identity — see
    # Glific.AI.Tool.Runner's moduledoc. That is a broken invariant, not a retryable failure.
    error in [Glific.AI.Actor.Error] -> {:permanent_error, error}
  end

  @spec run_tool_call(ToolCall.t(), Tool.Context.t(), module()) ::
          {:ok, message_attrs()} | {:error, term()}
  defp run_tool_call(%ToolCall{} = call, %Tool.Context{} = tool_context, skill) do
    output =
      case Jason.decode(call.function.arguments) do
        {:ok, arguments} -> tool_output(call, arguments, tool_context, skill)
        {:error, _reason} -> %{"error" => "Invalid arguments: not valid JSON."}
      end

    call.id
    |> Context.tool_result(call.function.name, output)
    |> build_message_attrs(request_id: tool_context.request_id)
  end

  @spec tool_output(ToolCall.t(), map(), Tool.Context.t(), module()) :: term()
  defp tool_output(%ToolCall{function: function}, arguments, tool_context, skill) do
    case Runner.call(function.name, arguments, tool_context, skill) do
      {:ok, result} -> result
      {:error, message} -> %{"error" => message}
    end
  end

  @spec assistant_message_attrs(State.t(), Result.t(), integer()) ::
          {:ok, message_attrs()} | {:error, term()}
  defp assistant_message_attrs(%State{} = state, %Result{message: message, usage: usage}, start) do
    build_message_attrs(message,
      request_id: state.conversation.active_request_id,
      model: state.skill.model(),
      prompt_tokens: usage.prompt,
      completion_tokens: usage.completion,
      cached_tokens: usage.cached,
      duration_ms: duration_ms(start)
    )
  end

  @spec build_message_attrs(Message.t(), keyword()) ::
          {:ok, message_attrs()} | {:error, term()}
  defp build_message_attrs(%Message{} = message, opts) do
    case Codec.encode(message) do
      {:ok, parts} ->
        {:ok,
         %{
           role: message.role,
           parts: parts,
           status: :complete,
           request_id: Keyword.get(opts, :request_id),
           model: Keyword.get(opts, :model),
           prompt_tokens: Keyword.get(opts, :prompt_tokens, 0),
           completion_tokens: Keyword.get(opts, :completion_tokens, 0),
           cached_tokens: Keyword.get(opts, :cached_tokens, 0),
           duration_ms: Keyword.get(opts, :duration_ms)
         }}

      {:error, reason} ->
        {:error, {:encode_failed, reason}}
    end
  end

  @spec model_opts(State.t()) :: keyword()
  defp model_opts(%State{} = state) do
    [model: state.skill.model(), api_key: state.api_key, cache_ttl: state.skill.cache_ttl()]
    |> maybe_put_tools(state.tools)
  end

  @spec maybe_put_tools(keyword(), [module()]) :: keyword()
  defp maybe_put_tools(opts, []), do: opts

  defp maybe_put_tools(opts, tools),
    do: Keyword.put(opts, :tools, Enum.map(tools, &to_req_tool/1))

  @spec to_req_tool(module()) :: ReqLLM.Tool.t()
  defp to_req_tool(tool) do
    {:ok, req_tool} =
      ReqLLM.Tool.new(
        name: tool.name(),
        description: tool.description(),
        parameter_schema: tool.parameters(),
        # Never invoked: ReqLLM requires a callback to build a Tool, but Glific always runs
        # tool calls itself through Glific.AI.Tool.Runner.call/4, never through ReqLLM's own
        # execution path (mirrors Glific.AI.Tool.Runner's own build_req_tool/1).
        callback: fn _args -> {:ok, nil} end
      )

    req_tool
  end

  @spec advance(State.t()) :: State.t()
  defp advance(%State{step_index: step_index} = state), do: %{state | step_index: step_index + 1}

  @spec derive_input(Context.t()) :: map()
  defp derive_input(%Context{messages: messages}) do
    case Enum.find(messages, &(&1.role == :user)) do
      nil -> %{}
      %Message{} = message -> %{"message" => text_content(message)}
    end
  end

  @spec text_content(Message.t()) :: String.t()
  defp text_content(%Message{content: parts}) do
    parts
    |> Enum.filter(&(&1.type == :text))
    |> Enum.map_join("", & &1.text)
  end

  @spec duration_ms(integer()) :: non_neg_integer()
  defp duration_ms(start_monotonic) do
    System.monotonic_time()
    |> Kernel.-(start_monotonic)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
