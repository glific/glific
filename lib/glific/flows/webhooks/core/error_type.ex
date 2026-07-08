defmodule Glific.Flows.Webhooks.ErrorType do
  @moduledoc """
  The allowed webhook error-type atoms and their bucket — single source of truth for the
  typed-return variant `{:error, ErrorType.t(), String.t()}`.

  A webhook module emits a stable atom (not prose), and `class/1` maps it to a bucket, so
  rewording the human message never remisclassifies. `Behaviour.error_class/1` can then be a
  one-liner: `def error_class(%{error_type: t}), do: ErrorType.class(t)`.

  See `plans/webhook-error-classification-skeleton.md`.
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

  @doc "Map an error-type atom to its bucket, or nil if unknown."
  @spec class(t() | nil) :: :config | :system | :transient | :stale | nil
  def class(_error_type) do
    # TODO: lookup in the @class map
    #   system   → kaapi_not_active, missing_api_key, tts_upload_failed
    #   config   → invalid_json_body, unknown_webhook_fn, invalid_media_url, assistant_not_found,
    #              invalid_geocoding, empty_input, flow_category_unmatched
    #   stale    → stale_callback
    #   transient→ rate_limited, service_unavailable
    nil
  end
end
