defmodule Glific.Flows.Webhooks.KaapiCallbackClassifier do
  @moduledoc """
  Classifies an async Kaapi callback failure into an `ErrorType.t()` so the shared
  `ErrorReporter` can route it — `:config` failures to `flow_webhook_config_errors` (notify
  support), everything else to `flow_webhooks` (page on-call).

  A sync webhook names its own failure inline (`{:error, ErrorType.t(), msg}` from `call/2`),
  but an async failure surfaces later, at callback time, as an **opaque string** from Kaapi —
  the node can't self-classify. So this module infers the class from the callback response the
  only signals available: a provider status code (nested `http_status`, or a `(code: NNN)` /
  `Status: NNN` embedded in the reason) and crash/overload signatures in the reason text.

  The DB `status_code` column is useless (`webhook.ex` hardcodes `400` for every failure), so
  classification never reads it — only the real status carried inside the callback body.
  See `plans/webhook-error-classification.md`.
  """

  alias Glific.Flows.Webhooks.ErrorType

  # A crash surfaces as a stacktrace/FunctionClauseError in the reason with no real status —
  # unjudgeable, so force system.
  @crash ~r/no function clause matching|is undefined|no match of right hand side|\*\* \(/

  # Upstream busy/overloaded/rate-limited. We do NOT retry, so the contact's message goes
  # unanswered — a real failure we page on (system), not an NGO-fixable config issue.
  @overloaded ~r/conversation_locked|Another process is currently operating|is overloaded|server_is_overloaded|rate limit|try again/i

  # Real provider status embedded in the reason string (never the DB status_code column).
  @code ~r/\(code:\s*(\d{3})|Status:\s*(\d{3})/

  @doc """
  Maps a failed Kaapi callback `result` to an `ErrorType.t()`.

  Config (NGO / flow-author fixable): the provider rejected our request with a 4xx (bad or
  unresolved input) → `:invalid_input`. Everything else fails safe to a system type: a crash,
  an overloaded upstream, a 408/429, a 5xx, or a statusless reason we can't judge.
  """
  @spec classify(map()) :: ErrorType.t()
  def classify(result) when is_map(result) do
    reason = to_reason(result)
    code = result["http_status"] || provider_status(reason)

    cond do
      reason =~ @crash -> :unknown
      reason =~ @overloaded -> :service_unavailable
      code in [408, 429] -> :rate_limited
      is_integer(code) and code in 400..499 -> :invalid_input
      is_integer(code) -> :unknown
      true -> :unknown
    end
  end

  def classify(_result), do: :unknown

  # A binary reason/error, else "" (a non-binary reason can't feed a regex → system fail-safe).
  @spec to_reason(map()) :: String.t()
  defp to_reason(%{"reason" => reason}) when is_binary(reason), do: reason
  defp to_reason(%{"error" => error}) when is_binary(error), do: error
  defp to_reason(%{reason: reason}) when is_binary(reason), do: reason
  defp to_reason(_result), do: ""

  @spec provider_status(String.t()) :: integer() | nil
  defp provider_status(reason) do
    case Regex.run(@code, reason) do
      [_, code] -> String.to_integer(code)
      [_, _, code] -> String.to_integer(code)
      _ -> nil
    end
  end
end
