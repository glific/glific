defmodule Glific.Flows.Webhooks.Behaviour do
  @moduledoc """
  Contract for a single flow-webhook node. Each implementation owns its integration code; the
  cross-cutting concerns (failure reporting, latency telemetry, WebhookLog, wait-state) live in
  `Dispatcher`/`Instrumentation`. Authors `use` the `Sync`/`Async` macros rather than
  implementing this directly.
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

  # Sync: {:ok, value} → Success branch; {:error, ErrorType.t(), msg} → Failure branch (the node
  # owns the config/system verdict, :unknown when it can't judge); {:snooze, seconds} reschedules
  # the Oban job. ResultTranslator normalises these into the map/string the flow engine routes on.
  @type sync_result ::
          {:ok, term()}
          | {:error, Glific.Flows.Webhooks.ErrorType.t(), String.t()}
          | {:snooze, pos_integer()}

  # Async (Kaapi): call/2 returns an ack map — %{success: true} parks the flow (resumed via the
  # Kaapi callback), %{success: false, reason} wakes it on Failure; {:snooze, seconds} reschedules
  # the Oban job. The flow's wait itself is set up in the flow engine (action.ex), not by this return.
  @type async_result :: map() | {:snooze, pos_integer()}

  @callback name() :: String.t()
  @callback mode() :: :sync | :async
  @callback call(fields :: map(), ctx :: ctx()) :: sync_result() | async_result()
  @callback wait_time_default() :: non_neg_integer()

  # Async callback phase (Kaapi POSTs back): `Dispatcher.callback` runs these through the same
  # instrumentation as `call/2`, so callback telemetry + error typing funnel through the
  # Dispatcher too. `callback/3` shapes the parsed response the flow resumes on (default passes
  # it through; voice-filesearch-gpt overrides it to post-process NMT+TTS). `classify/1` maps a
  # failed callback to an `ErrorType.t()` (default → `KaapiSupport.classify`; overridable).
  @callback callback(result :: map(), response :: map(), ctx :: ctx()) :: map()
  @callback classify(result :: map()) :: Glific.Flows.Webhooks.ErrorType.t()

  @optional_callbacks wait_time_default: 0, callback: 3, classify: 1
end
