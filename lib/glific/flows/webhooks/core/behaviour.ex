defmodule Glific.Flows.Webhooks.Behaviour do
  @moduledoc """
  Contract for a single flow-webhook node. Cross-cutting concerns (failure reporting, latency
  telemetry, WebhookLog, wait-state) live in `Dispatcher`/`Instrumentation` — authors `use` the
  `Sync`/`Async` macros rather than implementing this directly.
  """

  alias Glific.Flows.{Action, FlowContext}

  @type ctx :: %{
          required(:organization_id) => non_neg_integer() | nil,
          optional(:headers) => list(),
          optional(:flow_id) => non_neg_integer() | nil,
          optional(:contact_id) => non_neg_integer() | nil,
          optional(:flow_context_id) => non_neg_integer() | nil,
          optional(:wa_group_id) => non_neg_integer() | nil,
          optional(:webhook_log_id) => non_neg_integer(),
          optional(:action) => Action.t(),
          optional(:flow_context) => FlowContext.t()
        }

  # Sync and async nodes return the SAME typed result: `{:ok, value}` -> Success branch,
  # `{:error, ErrorType.t(), msg}` -> Failure branch, `{:snooze, seconds}` reschedules the Oban
  # job. For async (Kaapi) nodes `{:ok, ack}` means the dispatch was accepted and the flow parks
  # until the callback resumes it. `ResultTranslator` normalises this for the flow engine.
  @type result ::
          {:ok, term()}
          | {:error, Glific.Flows.Webhooks.ErrorType.t(), String.t()}
          | {:snooze, pos_integer()}

  @callback name() :: String.t()
  @callback mode() :: :sync | :async
  @callback call(fields :: map(), ctx :: ctx()) :: result()
  @callback wait_time_default() :: non_neg_integer()

  # Async callback phase (Kaapi POSTs back): `Dispatcher.callback` runs these through the same
  # instrumentation as `call/2`. `callback/3` shapes the response the flow resumes on (default
  # pass-through; voice-filesearch-gpt overrides it for NMT+TTS). `classify/1` maps a failed
  # callback to an `ErrorType.t()` (default -> `Kaapi.classify`; overridable).
  @callback callback(result :: map(), response :: map(), ctx :: ctx()) :: map()
  @callback classify(result :: map()) :: Glific.Flows.Webhooks.ErrorType.t()

  @optional_callbacks wait_time_default: 0, callback: 3, classify: 1
end
