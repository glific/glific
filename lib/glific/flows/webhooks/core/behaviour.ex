defmodule Glific.Flows.Webhooks.Behaviour do
  @moduledoc """
  Contract for a single flow-webhook node.

  A webhook implementation is one module, one file, that owns its own
  integration code (Tesla calls, Kaapi calls, payload building). Cross-cutting
  concerns — failure reporting, latency telemetry, WebhookLog row creation,
  wait-state management — are handled by `Glific.Flows.Webhooks.Dispatcher`
  and `Glific.Flows.Webhooks.Instrumentation`, not by the per-webhook module.

  Authors should `use Glific.Flows.Webhooks.Sync` or `Glific.Flows.Webhooks.Async`
  rather than implementing this behaviour directly — the macros inject
  `name/0` and `mode/0` and leave `call/2` (plus, for async, `handle_resume/2`)
  for the author to write.
  """

  alias Glific.Flows.{Action, FlowContext}
  alias Glific.Messages.Message

  @typedoc """
  Context passed to a webhook's `call/2`. Built by the dispatcher; carries
  enough state for the webhook to do its work and for instrumentation to
  attach the right AppSignal tags.

  Minimally `:organization_id` is set (may be `nil` when the field is
  absent or unparseable). Async webhooks additionally expect `:flow_context`,
  `:webhook_log_id`, `:action`, and the various ID fields used in the Kaapi
  request_metadata.
  """
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

  @typedoc """
  Return shape for synchronous webhooks. Matches today's
  `CommonWebhook.webhook/2,3` return contract: a map (success or failure
  shape), `nil`, or a bare string.

  `Glific.Flows.Webhook.handle` (private) coerces non-map results to `Failure`,
  so the shape stays flexible.
  """
  @type sync_result :: map() | nil | String.t()

  @typedoc """
  Return shape for migrated sync webhooks during the incremental refactor.

  Migrated modules return `{:ok, value}` or `{:error, message}` from `call/2`;
  `Glific.Flows.Webhooks.Dispatcher` applies
  `Glific.Flows.Webhooks.ResultTranslator.to_legacy_structure/2` to translate
  these into the legacy `sync_result` shape before passing the result to
  `Glific.Flows.Webhook.handle/3`.

  Remove this type once all webhooks are migrated and `handle/3` is updated.
  """
  @type migrated_sync_result :: {:ok, term()} | {:error, String.t()}

  @typedoc """
  Return shape for asynchronous webhooks (Kaapi STT/TTS, unified-llm-call,
  unified-voice-llm-call). `{:wait, ctx, []}` parks the flow context;
  `{:ok, ctx, [msg]}` is the immediate-failure branch (e.g. missing Kaapi
  creds, body decode error) where the flow continues with a Failure message
  without ever entering the await state.
  """
  @type async_result ::
          {:wait, FlowContext.t(), [Message.t()]}
          | {:ok, FlowContext.t(), [Message.t()]}

  @doc """
  The webhook's stable identifier — matches the URL string persisted in flow
  JSON (e.g. `"geolocation"`, `"speech_to_text"`).
  """
  @callback name() :: String.t()

  @doc """
  `:sync` for webhooks that return immediately, `:async` for ones that park
  the flow waiting for a Kaapi callback.
  """
  @callback mode() :: :sync | :async

  @doc """
  Execute the webhook. The dispatcher wraps this call with failure reporting
  and latency telemetry, so authors should NOT add their own `try`/`rescue`
  for AppSignal — let exceptions propagate.
  """
  @callback call(fields :: map(), ctx :: ctx()) ::
              sync_result | migrated_sync_result | async_result

  @doc """
  Async-only. Invoked from the flow_resume callback path to shape the Kaapi
  callback payload into the response map merged into the flow context.
  Defaults to `Glific.Flows.Webhooks.Callback.default_handle_resume/2` (mirrors
  today's `flow_resume_controller.do_flow_resume`). Override for webhooks
  whose callback needs post-processing (e.g. `unified-voice-llm-call`).
  """
  @callback handle_resume(callback :: map(), ctx :: ctx()) ::
              {:ok | :error, map()}

  @doc "Default Kaapi wait window in seconds. `60` for everything today."
  @callback wait_time_default() :: non_neg_integer()

  @optional_callbacks handle_resume: 2, wait_time_default: 0
end
