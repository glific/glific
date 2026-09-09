defmodule Glific.AI.Agent do
  @moduledoc """
  Runs one question through to an answer.

  Asks the model; if it requests tools, runs them and feeds the results back;
  repeats until it answers or a limit stops it. Every step is appended to
  `glific_ai_events`, so the next question can be answered with this one's
  context.

  Three configurable limits bound a run — a step count, a cost ceiling in USD
  across every model call, and a deadline. Whichever is reached first ends the
  run and records the reason on the message.
  """

  require Logger

  import Ecto.Query

  alias Glific.{
    AI,
    AI.ChatMessage,
    AI.Event,
    AI.Instrumentation,
    AI.Message,
    AI.Provider,
    AI.Router,
    AI.Skills,
    AI.Tools,
    Repo,
    Users.User
  }

  @zero_usage %{input_tokens: 0, output_tokens: 0, cost: 0}

  @typedoc "One `(message_id, step, type, content)` row of a conversation."
  @type row() :: {non_neg_integer(), pos_integer(), atom(), String.t() | nil}

  @typedoc """
  What a run accumulates as it goes.

  `step` is the next event number to hand out and `steps` is what the ceiling
  bounds — they differ because routing takes a number without spending budget.
  Both are held here rather than read back from the events table.
  """
  @type run() :: %{
          usage: Provider.usage(),
          step: pos_integer(),
          steps: non_neg_integer(),
          answer_event_id: non_neg_integer() | nil
        }

  @typedoc "What the caller needs that is not the answer itself."
  @type meta() :: %{skill: String.t(), answer_event_id: non_neg_integer() | nil}

  @typep outcome() :: {:ok, String.t(), run()} | {:stopped, String.t(), run()}

  @doc """
  Runs a message to completion and returns the answer.

  Pass `skill:` to invoke one directly — that is how a button in the UI reaches a
  specific skill. Without it the intent is classified first.

  Returns the answer along with which skill produced it and the event it was
  recorded as, so a caller needs no further reads. The message row is written
  once at the end with the skill, the model, the outcome, the cost and, on
  failure, the reason.
  """
  @spec run(Message.t(), User.t(), keyword()) ::
          {:ok, String.t(), meta()} | {:error, String.t()}
  def run(%Message{} = message, %User{} = user, opts \\ []) do
    started_at = System.monotonic_time(:millisecond)
    thread = thread(message)

    case resolve_skill(thread, message, opts) do
      {:ok, skill, usage, classified?} ->
        run = record_routing(message, skill, usage, classified?, start(thread, message, usage))

        ctx = %{
          organization_id: message.organization_id,
          model: Provider.impl().model(opts),
          skill: skill,
          tools: Skills.tools(skill),
          modules: Skills.modules(skill),
          started_at: started_at,
          deadline: started_at + limits()[:max_run_duration_ms]
        }

        messages = [ChatMessage.system(skill.prompt()) | Enum.map(thread, &to_chat_message/1)]

        message
        |> loop(user, messages, run, ctx)
        |> finish(message, ctx)

      {:error, reason} ->
        message |> Message.changeset(%{status: :failed, error: reason}) |> Repo.update!()

        Instrumentation.question(%{
          skill: "unresolved",
          outcome: "rejected",
          duration_ms: System.monotonic_time(:millisecond) - started_at,
          cost: 0
        })

        {:error, reason}
    end
  end

  @spec resolve_skill([row()], Message.t(), keyword()) ::
          {:ok, module(), Provider.usage(), boolean()} | {:error, String.t()}
  defp resolve_skill(thread, message, opts) do
    case Keyword.get(opts, :skill) do
      blank when blank in [nil, ""] ->
        {skill, usage, classified?} =
          Router.classify(message.organization_id, question(thread), opts)

        {:ok, skill, usage, classified?}

      name ->
        with {:ok, skill} <- Skills.fetch(name), do: {:ok, skill, @zero_usage, false}
    end
  end

  @spec record_routing(Message.t(), module(), Provider.usage(), boolean(), run()) :: run()
  defp record_routing(_message, _skill, _usage, false, run), do: run

  defp record_routing(message, skill, usage, true, run) do
    append(
      message,
      :routing,
      skill.name(),
      %{
        "input_tokens" => usage.input_tokens,
        "output_tokens" => usage.output_tokens,
        "cost" => usage.cost
      },
      nil,
      run.step
    )

    %{run | step: run.step + 1}
  end

  @spec question([row()]) :: String.t()
  defp question(thread) do
    thread
    |> Enum.reverse()
    |> Enum.find_value("", fn
      {_message_id, _step, :user, content} -> content
      _ -> nil
    end)
    |> to_string()
  end

  @spec loop(Message.t(), User.t(), [ChatMessage.t()], run(), map()) :: outcome()
  defp loop(message, user, messages, run, ctx) do
    cond do
      run.steps >= limits()[:max_run_steps] ->
        {:stopped, "Reached the limit of #{limits()[:max_run_steps]} steps without finishing.",
         run}

      run.usage.cost > limits()[:max_run_cost] ->
        {:stopped,
         "Reached the cost ceiling of $#{limits()[:max_run_cost_usd]} for one question.", run}

      System.monotonic_time(:millisecond) > ctx.deadline ->
        {:stopped, "Took longer than #{div(limits()[:max_run_duration_ms], 1000)}s to answer.",
         run}

      true ->
        take_turn(message, user, messages, run, ctx)
    end
  end

  @spec take_turn(Message.t(), User.t(), [ChatMessage.t()], run(), map()) :: outcome()
  defp take_turn(message, user, messages, run, ctx) do
    case AI.generate(ctx.organization_id, messages, model: ctx.model, tools: ctx.tools) do
      {:ok, reply, call_usage} ->
        handle_reply(message, user, messages, reply, spend(run, call_usage), ctx)

      {:error, reason} ->
        {:stopped, describe(reason), run}
    end
  end

  @spec handle_reply(
          Message.t(),
          User.t(),
          [ChatMessage.t()],
          ChatMessage.t(),
          run(),
          map()
        ) :: outcome()
  defp handle_reply(message, _user, _messages, %ChatMessage{tool_calls: []} = reply, run, _ctx) do
    event = append(message, :assistant, reply.content, %{}, nil, run.step)
    {:ok, reply.content || "", %{run | answer_event_id: event.id}}
  end

  defp handle_reply(message, user, messages, reply, run, ctx) do
    {results, run} = run_tools(message, user, reply.tool_calls, run, ctx.modules)

    loop(message, user, messages ++ [reply | results], run, ctx)
  end

  @spec run_tools(Message.t(), User.t(), [ChatMessage.tool_call()], run(), [module()]) ::
          {[ChatMessage.t()], run()}
  defp run_tools(message, user, calls, run, modules) do
    {running, skipped} = Enum.split(calls, affordable(run))

    numbered = Enum.with_index(running)

    Enum.each(numbered, fn {call, index} ->
      append(
        message,
        :tool_call,
        call.name,
        %{"arguments" => call.args},
        call.id,
        run.step + index * 2
      )
    end)

    results =
      numbered
      |> Task.async_stream(
        fn {call, index} -> run_tool(message, user, call, run.step + index * 2 + 1, modules) end,
        max_concurrency: max(length(running), 1),
        timeout: limits()[:max_run_duration_ms],
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.zip(numbered)
      |> Enum.map(fn
        {{:ok, result}, _} -> result
        {{:exit, reason}, {call, index}} -> died(message, call, run.step + index * 2 + 1, reason)
      end)

    taken = 2 * length(running)

    steps = if skipped == [], do: run.steps + taken, else: limits()[:max_run_steps]

    {results ++ Enum.map(skipped, &out_of_steps/1), %{run | step: run.step + taken, steps: steps}}
  end

  @spec affordable(run()) :: non_neg_integer()
  defp affordable(run) do
    (limits()[:max_run_steps] - run.steps)
    |> max(0)
    |> div(2)
  end

  @spec out_of_steps(ChatMessage.tool_call()) :: ChatMessage.t()
  defp out_of_steps(call), do: failed(call, :out_of_steps)

  @spec died(Message.t(), ChatMessage.tool_call(), pos_integer(), term()) :: ChatMessage.t()
  defp died(message, call, step, reason) do
    result = failed(call, reason)

    append(message, :tool_result, nil, %{"output" => result.content}, call.id, step)
    result
  end

  @spec failed(ChatMessage.tool_call(), term()) :: ChatMessage.t()
  defp failed(%{id: id, name: name}, reason),
    do: ChatMessage.tool_result(id, name, Jason.encode!(%{error: describe_failure(reason)}))

  @spec describe_failure(term()) :: String.t()
  defp describe_failure(:out_of_steps), do: "Not run: this question has reached its step limit."
  defp describe_failure(:timeout), do: "The lookup timed out."

  defp describe_failure(reason) do
    Logger.error("Glific AI tool task exited: #{Glific.SafeLog.safe_inspect(reason)}")
    "The lookup stopped before it finished."
  end

  @spec run_tool(Message.t(), User.t(), ChatMessage.tool_call(), pos_integer(), [module()]) ::
          ChatMessage.t()
  defp run_tool(message, user, %{id: id, name: name, args: args}, step, modules) do
    body =
      case Tools.run(name, args, user, modules) do
        {:ok, result} -> encode(result)
        {:error, reason} -> Jason.encode!(%{error: reason})
      end

    append(message, :tool_result, nil, %{"output" => body}, id, step)
    ChatMessage.tool_result(id, name, body)
  end

  @spec finish(outcome(), Message.t(), map()) ::
          {:ok, String.t(), meta()} | {:error, String.t()}
  defp finish({:ok, answer, run}, message, ctx) do
    record(message, %{status: :succeeded}, run, ctx)
    measure("succeeded", run, ctx)
    {:ok, answer, %{skill: ctx.skill.name(), answer_event_id: run.answer_event_id}}
  end

  defp finish({:stopped, reason, run}, message, ctx) do
    record(message, %{status: :failed, error: reason}, run, ctx)
    measure("failed", run, ctx)
    {:error, reason}
  end

  @spec measure(String.t(), run(), map()) :: :ok
  defp measure(outcome, run, ctx) do
    Instrumentation.question(%{
      skill: ctx.skill.name(),
      outcome: outcome,
      duration_ms: System.monotonic_time(:millisecond) - ctx.started_at,
      cost: run.usage.cost
    })
  end

  @spec record(Message.t(), map(), run(), map()) :: Message.t()
  defp record(message, attrs, run, ctx) do
    message
    |> Message.changeset(
      Map.merge(attrs, %{
        model: ctx.model,
        skill: ctx.skill.name(),
        input_tokens: run.usage.input_tokens,
        output_tokens: run.usage.output_tokens,
        cost: run.usage.cost
      })
    )
    |> Repo.update!()
  end

  @spec thread(Message.t()) :: [row()]
  defp thread(message) do
    Event
    |> where([e], e.conversation_id == ^message.conversation_id)
    |> where([e], e.type in [:user, :assistant])
    |> order_by([e], asc: e.message_id, asc: e.step)
    |> select([e], {e.message_id, e.step, e.type, e.content})
    |> Repo.all()
  end

  @spec to_chat_message(row()) :: ChatMessage.t()
  defp to_chat_message({_message_id, _step, :assistant, content}),
    do: ChatMessage.assistant(content || "")

  defp to_chat_message({_message_id, _step, _user, content}),
    do: ChatMessage.user(content || "")

  @spec start([row()], Message.t(), Provider.usage()) :: run()
  defp start(thread, message, usage) do
    mine = Enum.filter(thread, fn {message_id, _, _, _} -> message_id == message.id end)
    highest = mine |> Enum.map(fn {_, step, _, _} -> step end) |> Enum.max(fn -> 0 end)

    %{usage: usage, step: highest + 1, steps: 0, answer_event_id: nil}
  end

  @spec append(Message.t(), atom(), String.t() | nil, map(), String.t() | nil, pos_integer()) ::
          Event.t()
  defp append(message, type, content, data, tool_call_id, step) do
    %Event{}
    |> Event.changeset(%{
      message_id: message.id,
      conversation_id: message.conversation_id,
      organization_id: message.organization_id,
      step: step,
      type: type,
      content: content,
      data: data,
      tool_call_id: tool_call_id
    })
    |> Repo.insert!()
  end

  @spec encode(term()) :: String.t()
  defp encode(result) do
    case Jason.encode(result) do
      {:ok, json} -> json
      {:error, _} -> Glific.SafeLog.safe_inspect(result)
    end
  end

  @spec spend(run(), Provider.usage()) :: run()
  defp spend(run, call) do
    %{
      run
      | usage: %{
          input_tokens: run.usage.input_tokens + call.input_tokens,
          output_tokens: run.usage.output_tokens + call.output_tokens,
          cost: run.usage.cost + call.cost
        }
    }
  end

  @spec limits() :: keyword()
  defp limits do
    defaults = [max_run_steps: 12, max_run_cost_usd: "0.50", max_run_duration_ms: 120_000]

    config =
      :glific
      |> Application.get_env(__MODULE__, [])
      |> then(&Keyword.merge(defaults, &1))

    Keyword.put(
      config,
      :max_run_cost,
      config[:max_run_cost_usd] |> Decimal.new() |> Decimal.to_float()
    )
  end

  @spec describe(:disabled | Provider.failure()) :: String.t()
  defp describe(:disabled), do: "Glific AI is not enabled for this organisation."
  defp describe({_kind, message}), do: message
end
