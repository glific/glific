defmodule Glific.AI.Telemetry.Context do
  @moduledoc """
  Process-dictionary carrier for the caller context a span needs but a `:telemetry` handler
  has no argument to receive.

  `ReqLLM.OpenTelemetry`'s bridge handler runs synchronously in the same process as the model
  call, so it *could* read caller identity if it had a way to ask for it — but it is a stateless
  module driven entirely by `:telemetry` event metadata, and that metadata is `req_llm`'s own
  request/response shape, not ours. `Glific.AI.Telemetry.OTelAdapter.start_span/3` is where we
  inject Glific-specific attributes onto the span, and the only channel available to it, given
  `req_llm` calls it with no notion of "current Glific user", is the process dictionary of the
  process it happens to be running in.

  That process is not always the one that called `ReqLLM.generate_text/3`. In particular,
  `Glific.AI.StepWorker.run_with_timeout/1` runs each step in a `Task.async` child so a stuck
  model call can be killed on a wall-clock timeout without killing the Oban job — and a freshly
  spawned task starts with an empty process dictionary. The context must therefore be set
  *inside* that task, next to the existing `Glific.AI.Actor.reinstate!/2` call, not in the
  parent process that scheduled it.
  """

  @context_key :glific_ai_telemetry_context
  @fields ~w(organization_id user_id request_id skill step_index conversation_id)a

  @typedoc "Caller context attached to AI runtime spans and AppSignal tags."
  @type t :: %{
          optional(:organization_id) => non_neg_integer(),
          optional(:user_id) => non_neg_integer(),
          optional(:request_id) => String.t(),
          optional(:skill) => String.t(),
          optional(:step_index) => non_neg_integer(),
          optional(:conversation_id) => non_neg_integer()
        }

  @doc "Stores the caller context in the current process's dictionary."
  @spec put(t()) :: :ok
  def put(context) when is_map(context) do
    Process.put(@context_key, Map.take(context, @fields))
    :ok
  end

  @doc "Returns the caller context for the current process, or `%{}` when unset."
  @spec get() :: t()
  def get, do: Process.get(@context_key) || %{}

  @doc "Clears the caller context from the current process's dictionary."
  @spec clear() :: :ok
  def clear do
    Process.delete(@context_key)
    :ok
  end
end
