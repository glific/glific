defmodule Glific.Providers.Instrumentation.Behaviour do
  @moduledoc """
  Contract for a provider's instrumentation adapter.

  A provider gets the standard metrics for free by `use`-ing
  `Glific.Providers.Instrumentation.Adapter`, which supplies default
  implementations of both callbacks. A provider only writes code here when it
  needs custom behaviour — e.g. Gupshup overriding `classify_send/2` to record a
  frequency-capped send under its own status.
  """

  @doc "Provider tag stamped on every metric (e.g. `\"gupshup\"`)."
  @callback provider() :: String.t()

  @doc """
  Reclassify a raw send outcome into the final status recorded on
  `provider_send_count`.

  `status` is the raw outcome (`:success` | `:error` | `:timeout`); `context` is
  whatever the call site passed to `track_send/3` (e.g. `%{error_code: 472}`).
  The default implementation returns `status` unchanged; override to add
  provider-specific classification.
  """
  @callback classify_send(status :: atom(), context :: map()) :: atom()
end
