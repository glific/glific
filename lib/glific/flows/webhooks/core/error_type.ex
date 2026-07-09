defmodule Glific.Flows.Webhooks.ErrorType do
  @moduledoc """
  The allowed sync-webhook error-type atoms and their bucket — single source of truth for the
  typed-return variant `{:error, ErrorType.t(), String.t()}`.

  A sync webhook classifies its own failures: `call/2` returns `{:error, ErrorType.t(), message}`
  with a stable atom (not prose), and `class/1` maps that atom to a bucket. `Instrumentation`
  reads the atom off the return value and reports the class directly — the module owns the
  verdict, there is no central heuristic in the sync path. `:unknown` is the in-module fail-safe
  for a failure the node genuinely can't judge (→ `:system`, so it still pages).

  (Async / Kaapi callbacks are classified separately and are out of scope here.)

  See `plans/webhook-error-classification.md`.
  """

  @type t ::
          :missing_api_key
          | :invalid_media_url
          | :invalid_geocoding
          | :empty_input
          | :invalid_input
          | :rate_limited
          | :service_unavailable
          | :unknown

  # A Glific-owned provisioning/infra gap or an unjudgeable failure (system) pages on-call; an
  # NGO/flow-author mistake (config) notifies support; an upstream blip (transient) is
  # rate-monitored (no incident).
  @class %{
    missing_api_key: :system,
    unknown: :system,
    invalid_media_url: :config,
    invalid_geocoding: :config,
    empty_input: :config,
    invalid_input: :config,
    rate_limited: :transient,
    service_unavailable: :transient
  }

  @doc "Map an error-type atom to its bucket, or `nil` if unrecognised (caller fails safe to system)."
  @spec class(t() | nil) :: :config | :system | :transient | nil
  def class(error_type), do: Map.get(@class, error_type)
end
