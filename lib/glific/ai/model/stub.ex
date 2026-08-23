defmodule Glific.AI.Model.Stub do
  @moduledoc """
  Deterministic, scriptable `Glific.AI.Model` adapter for tests. Selected via
  `config :glific, :ai_model_adapter, Glific.AI.Model.Stub` in `config/test.exs`.

  Every runtime test above the model-call layer scripts this adapter instead of touching a
  provider — a test that makes a real outbound call is a bug (`test/CLAUDE.md`). Queue a
  response with `queue_text/1`, `queue_tool_calls/1`, `queue_object/1`, or `queue_error/1`, in
  the order calls are expected to happen; `chat/2` and `object/3` pop the next one and record the
  context they were called with, so a test can assert both the scripted outcome and exactly what
  the runtime sent upstream via `calls/0`.

  Backed by a named `Agent` so state survives the process boundaries a real runtime step
  crosses (e.g. an Oban job). Start it once per test — `start_supervised!(Glific.AI.Model.Stub)`
  — and call `reset/0` between steps that reuse the same test.
  """

  use Agent

  @behaviour Glific.AI.Model

  alias Glific.AI.Codec
  alias Glific.AI.Model.Result
  alias Glific.AI.Skill
  alias ReqLLM.Context

  @typedoc "Builds the response `chat/2`/`object/3` returns from the context it was called with."
  @type thunk :: (Context.t() -> {:ok, term()} | {:error, term()})

  @doc "Starts the stub with an empty queue."
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts \\ []),
    do: Agent.start_link(fn -> %{queue: [], calls: []} end, name: __MODULE__)

  @doc "Clears the queue and the recorded calls."
  @spec reset() :: :ok
  def reset, do: Agent.update(__MODULE__, fn _state -> %{queue: [], calls: []} end)

  @doc "Queues a `chat/2` result: a plain-text assistant reply, `finish_reason: :stop`."
  @spec queue_text(String.t()) :: :ok
  def queue_text(text) when is_binary(text), do: enqueue(&text_response(&1, text))

  @doc "Queues a `chat/2` result carrying tool calls, `finish_reason: :tool_calls`."
  @spec queue_tool_calls([ReqLLM.ToolCall.t()]) :: :ok
  def queue_tool_calls(tool_calls) when is_list(tool_calls),
    do: enqueue(&tool_calls_response(&1, tool_calls))

  @doc "Queues an `object/3` result: the exact map `object/3` returns on success."
  @spec queue_object(map()) :: :ok
  def queue_object(object) when is_map(object), do: enqueue(fn _context -> {:ok, object} end)

  @doc "Queues an error, returned as-is by whichever of `chat/2`/`object/3` is called next."
  @spec queue_error(term()) :: :ok
  def queue_error(reason), do: enqueue(fn _context -> {:error, reason} end)

  @doc "Every context this adapter has been called with, oldest first."
  @spec calls() :: [Context.t()]
  def calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.calls))

  @impl true
  @spec chat(Context.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def chat(%Context{} = context, _opts), do: pop(context)

  @impl true
  @spec object(Context.t(), Skill.output_schema(), keyword()) :: {:ok, map()} | {:error, term()}
  def object(%Context{} = context, _schema, _opts), do: pop(context)

  @spec enqueue(thunk()) :: :ok
  defp enqueue(thunk),
    do: Agent.update(__MODULE__, fn state -> %{state | queue: state.queue ++ [thunk]} end)

  @spec pop(Context.t()) :: {:ok, term()} | {:error, term()}
  defp pop(context) do
    Agent.get_and_update(__MODULE__, fn
      %{queue: [thunk | rest]} = state ->
        {thunk.(context), %{state | queue: rest, calls: [context | state.calls]}}

      %{queue: []} = state ->
        {{:error, :stub_queue_empty}, %{state | calls: [context | state.calls]}}
    end)
  end

  @spec text_response(Context.t(), String.t()) :: {:ok, Result.t()}
  defp text_response(context, text) do
    message = text |> Context.assistant() |> Codec.normalize()

    {:ok,
     %Result{
       message: message,
       tool_calls: [],
       finish_reason: :stop,
       usage: Result.zero_usage(),
       context: Context.append(context, message)
     }}
  end

  @spec tool_calls_response(Context.t(), [ReqLLM.ToolCall.t()]) :: {:ok, Result.t()}
  defp tool_calls_response(context, tool_calls) do
    message = "" |> Context.assistant(tool_calls: tool_calls) |> Codec.normalize()

    {:ok,
     %Result{
       message: message,
       tool_calls: tool_calls,
       finish_reason: :tool_calls,
       usage: Result.zero_usage(),
       context: Context.append(context, message)
     }}
  end
end
