defmodule Glific.Flows.Webhooks.ErrorType do
  @moduledoc """
  The allowed webhook error-type atoms and their bucket — single source of truth for the
  typed-return variant `{:error, ErrorType.t(), String.t()}`.

  A sync webhook emits a stable atom (not prose) as part of its `call/2` return —
  `{:error, ErrorType.t(), message}` — and `class/1` maps it to a bucket, so rewording the
  human message never remisclassifies. `Instrumentation` reads the atom off the returned value
  and reports the class directly (unidirectional — no call back into the module).

  See `plans/webhook-error-classification.md`.
  """

  @type t ::
          :kaapi_not_active
          | :missing_api_key
          | :tts_upload_failed
          | :invalid_json_body
          | :unknown_webhook_fn
          | :invalid_media_url
          | :assistant_not_found
          | :invalid_geocoding
          | :empty_input
          | :flow_category_unmatched
          | :stale_callback
          | :rate_limited
          | :service_unavailable

  # A Glific-owned provisioning/infra gap (system) pages on-call; an NGO/flow-author mistake
  # (config) notifies support; an upstream blip (transient) is rate-monitored; a benign race
  # (stale) is suppressed. See the buckets in `Glific.Flows.Webhooks.ErrorClassifier`.
  @class %{
    kaapi_not_active: :system,
    missing_api_key: :system,
    tts_upload_failed: :system,
    invalid_json_body: :config,
    unknown_webhook_fn: :config,
    invalid_media_url: :config,
    assistant_not_found: :config,
    invalid_geocoding: :config,
    empty_input: :config,
    flow_category_unmatched: :config,
    stale_callback: :stale,
    rate_limited: :transient,
    service_unavailable: :transient
  }

  @doc "Map an error-type atom to its bucket, or nil if unknown (caller defers to the engine)."
  @spec class(t() | nil) :: :config | :system | :transient | :stale | nil
  def class(error_type), do: Map.get(@class, error_type)
end
