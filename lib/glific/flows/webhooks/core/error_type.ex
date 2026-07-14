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

  @doc "Map an error-type atom to its bucket (:config / :system), or nil if unrecognised."
  @spec class(t() | nil) :: :config | :system | nil
  def class(error_type), do: Map.get(@class, error_type)

  @doc """
  Map a raw HTTP status to an `t()` so any webhook — sync, async dispatch, or a provider call
  like Gemini STT — buckets a status the same way. A 408/429 is an upstream blip
  (`:rate_limited` → system, since we do not retry), any other 4xx is a rejected request
  (`:invalid_input` → config), and everything else (5xx, a transport atom like `:timeout`, a
  raw body, `nil`) fails safe to `:unknown` → system.

  ## Examples

      iex> Glific.Flows.Webhooks.ErrorType.from_http_status(400)
      :invalid_input

      iex> Glific.Flows.Webhooks.ErrorType.from_http_status(429)
      :rate_limited

      iex> Glific.Flows.Webhooks.ErrorType.from_http_status(500)
      :unknown

      iex> Glific.Flows.Webhooks.ErrorType.from_http_status(:timeout)
      :unknown
  """
  @spec from_http_status(any()) :: t()
  def from_http_status(status) when status in [408, 429], do: :rate_limited
  def from_http_status(status) when is_integer(status) and status in 400..499, do: :invalid_input
  def from_http_status(_status), do: :unknown
end
