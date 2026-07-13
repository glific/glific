defmodule Glific.Flows.Webhooks.ErrorType do
  @moduledoc """
  Allowed sync-webhook error-type atoms and their bucket — the single source of truth for the
  typed `{:error, ErrorType.t(), String.t()}` return. A sync node names its own failure with an
  atom; `class/1` maps it to `:config`/`:system` (`:unknown` is the fail-safe → `:system`).
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

  # system pages on-call, config notifies support. There is no retry, so an upstream blip
  # (rate-limit / service-unavailable) is a real failure we page on (system), not suppressed.
  @class %{
    missing_api_key: :system,
    unknown: :system,
    rate_limited: :system,
    service_unavailable: :system,
    invalid_media_url: :config,
    invalid_geocoding: :config,
    empty_input: :config,
    invalid_input: :config
  }

  @spec class(t() | nil) :: :config | :system | nil
  def class(error_type), do: Map.get(@class, error_type)
end
