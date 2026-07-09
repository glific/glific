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

  The `result` map passed in is normalised by the caller to atom keys — at least `:reason`
  (a string) and optionally `:http_status` (the *real* provider status, never the hardcoded
  `webhook_logs.status_code` column). Per-module `error_class/1` clauses match on the same
  atom-keyed shape.

  See `plans/webhook-error-classification.md`.
  """

  alias Glific.Flows.Webhooks.Errors

  @crash ~r/no function clause matching|is undefined|no match of right hand side|\*\* \(/
  @transient ~r/conversation_locked|Another process is currently operating|is overloaded|server_is_overloaded|rate limit|try again/
  @code ~r/\(code:\s*(\d{3})|Status:\s*(\d{3})/

  @type class :: :config | :system | :transient | :stale

  @doc """
  Classify a failure. The webhook module's `error_class/1` verdict wins; `nil` defers to the
  engine `heuristic/1`. `module` is `nil` on the legacy stack / resume path.
  """
  @spec classify(module() | nil, map()) :: class()
  def classify(module, result) do
    cond do
      module && function_exported?(module, :error_class, 1) ->
        module.error_class(result) || heuristic(result)

      true ->
        heuristic(result)
    end
  end

  @doc """
  Fallback classifier for external provider errors (no module verdict). Uses the real provider
  status (nested `:http_status`, or a code parsed from the message) plus reason patterns — never
  the hardcoded `webhook_logs.status_code` column.

  Order: crash-signature → transient → 408/429 → 4xx (config) / 5xx (system) → fail-safe system.
  """
  @spec heuristic(map()) :: class()
  def heuristic(result) do
    reason = to_reason(result)
    code = result[:http_status] || provider_status(reason)

    cond do
      reason =~ @crash -> :system
      reason =~ @transient -> :transient
      code in [408, 429] -> :transient
      is_integer(code) and code in 400..499 -> :config
      is_integer(code) -> :system
      true -> :system
    end
  end

  @doc "Map a class to an action: report under a namespace, count only, or suppress."
  @spec route(class()) :: {:report, String.t()} | :count | :suppress
  def route(:system), do: {:report, "flow_webhooks"}
  def route(:config), do: {:report, "flow_webhook_config_errors"}
  def route(:transient), do: :count
  def route(:stale), do: :suppress

  @doc """
  Perform the action for `class`: for `:system`/`:config` build the matching exception with a
  low-cardinality message and send via `Glific.log_exception/2` under the routed namespace;
  `:transient`/`:stale` emit no incident. Every class bumps `flow_webhook_count` with an
  `error_type` tag so the split is chartable.

  `tags` must include `:webhook_name`; per-occurrence detail (org, status, reason) rides along.
  """
  @spec report(class(), map(), map()) :: :ok
  def report(class, result, tags) do
    webhook_name = tags[:webhook_name]

    case route(class) do
      {:report, namespace} ->
        reason = to_reason(result)

        exception =
          case class do
            :config ->
              %Errors.ConfigurationError{message: "Webhook config_error from #{webhook_name}"}

            _ ->
              %Errors.SystemError{message: "Webhook system_error from #{webhook_name}"}
          end

        Glific.log_exception(exception,
          namespace: namespace,
          tags: Map.merge(tags, %{reason: reason, error_type: to_string(class)})
        )

      _count_or_suppress ->
        :ok
    end

    track_count(webhook_name, class)
    :ok
  end

  @spec track_count(String.t() | nil, class()) :: :ok
  defp track_count(webhook_name, class) do
    Appsignal.increment_counter("flow_webhook_count", 1, %{
      webhook_name: webhook_name || "unknown",
      status: "failure",
      error_type: to_string(class)
    })

    :ok
  end

  @spec to_reason(map()) :: String.t()
  defp to_reason(result) do
    case result[:reason] || result[:error] || result[:message] do
      reason when is_binary(reason) -> reason
      _ -> ""
    end
  end

  @spec provider_status(String.t()) :: integer() | nil
  defp provider_status(reason) do
    case Regex.run(@code, reason) do
      [_, code] -> String.to_integer(code)
      [_, _, code] -> String.to_integer(code)
      _ -> nil
    end
  end
end
