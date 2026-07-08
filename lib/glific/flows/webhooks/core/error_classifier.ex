defmodule Glific.Flows.Webhooks.ErrorClassifier do
  @moduledoc """
  Central engine that turns a webhook failure into a bucket and routes the observability signal.

  A failure is classified into one of:

    * `:system`    — provider 5xx / unreachable / our crash → **pages on-call** (`flow_webhooks`)
    * `:config`    — NGO / flow-author misconfiguration → **notifies support** (`flow_webhook_config_errors`)
    * `:transient` — retryable upstream blip (conversation_locked, overloaded) → metric only, no incident
    * `:stale`     — late/duplicate callback ("no active flows") → suppressed, counter only

  `classify/2` asks the webhook module's `Behaviour.error_class/1` first (deterministic,
  per-module), then falls back to `heuristic/1` for external/untyped errors. `route/1` maps a
  class to an action; `report/3` performs it.

  See `plans/webhook-error-classification.md` and `...-skeleton.md`.
  """

  @type class :: :config | :system | :transient | :stale

  @doc """
  Classify a failure. The webhook module's `error_class/1` verdict wins; `nil` defers to the
  engine `heuristic/1`. `module` is `nil` on the legacy stack / resume path.
  """
  @spec classify(module() | nil, map()) :: class()
  def classify(module, result) do
    # TODO: module verdict wins, else heuristic/1
    cond do
      module && function_exported?(module, :error_class, 1) ->
        module.error_class(result) || heuristic(result)

      true ->
        heuristic(result)
    end
  end

  @doc """
  Fallback classifier for external provider errors (no module verdict). Uses the real provider
  status (nested `http_status`, or a code parsed from the message) plus reason patterns — never
  the hardcoded `webhook_logs.status_code` column.

  Order: crash-signature → transient → 4xx (config) / 5xx (system) → fail-safe system.
  """
  @spec heuristic(map()) :: class()
  def heuristic(_result) do
    # TODO: crash | transient(before status) | 408/429→transient | 4xx→config | 5xx→system | fail-safe :system
    :system
  end

  @doc "Map a class to an action: report under a namespace, count only, or suppress."
  @spec route(class()) :: {:report, String.t()} | :count | :suppress
  def route(_class) do
    # TODO: :system→{:report,"flow_webhooks"} :config→{:report,"flow_webhook_config_errors"}
    #       :transient→:count  :stale→:suppress
    :suppress
  end

  @doc """
  Perform the action for `class`: build the exception (`ConfigurationError`/`SystemError`) with a
  low-cardinality message + detail tags and send via `Glific.log_exception/2` under the routed
  namespace, or just increment the `flow_webhook_count` metric (transient/stale).
  """
  @spec report(class(), map(), map()) :: :ok
  def report(_class, _result, _tags) do
    # TODO: reason from result; exception per class; Glific.log_exception(namespace:, tags:);
    #       track flow_webhook_count with error_type
    :ok
  end
end
