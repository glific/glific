defmodule Glific.Flows.Webhooks.Behaviour do
  @moduledoc """
  Contract for a single flow-webhook node. Each implementation owns its integration code; the
  cross-cutting concerns (failure reporting, latency telemetry, WebhookLog, wait-state) live in
  `Dispatcher`/`Instrumentation`. Authors `use` the `Sync`/`Async` macros rather than
  implementing this directly.
  """

  alias Glific.Flows.{Action, FlowContext}
  alias Glific.Messages.Message

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

  # Async webhooks: {:wait, ctx, []} parks the flow context; {:ok, ctx, [msg]} is the
  # immediate-failure branch (flow continues on a Failure message without entering await).
  @type async_result ::
          {:wait, FlowContext.t(), [Message.t()]}
          | {:ok, FlowContext.t(), [Message.t()]}

  @callback name() :: String.t()
  @callback mode() :: :sync | :async
  @callback call(fields :: map(), ctx :: ctx()) :: sync_result() | async_result()
  @callback wait_time_default() :: non_neg_integer()

  @optional_callbacks wait_time_default: 0
end
