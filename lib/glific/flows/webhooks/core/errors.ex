defmodule Glific.Flows.Webhooks.Errors do
  @moduledoc """
  Exception types for the `Glific.Flows.Webhooks` subsystem.

  These are the single home for webhook error reporting. The legacy `Glific.Flows.Webhook`
  reporting path (`report_to_appsignal/2` + its `SystemError`/`TimeoutError`) has been removed;
  `Glific.Flows.Webhook.Error` remains only as the Kaapi-worker exception. New code in the
  `Webhooks` namespace raises and reports the types below.

  Three exception classes mirror the failure modes of the webhook execution pipeline:

  - `SystemError` — the webhook call itself failed (HTTP error, API rejection, parse
    failure). Raised or constructed in `Instrumentation.around/3`.
  - `TimeoutError` — an async webhook's await window expired without a callback.
    Raised in `Instrumentation.report_timeout/1`.
  - `Error` — general-purpose; for failures that don't fit the above categories.

  `ConfigurationError` is intentionally absent — there are no concrete missing-credential
  scenarios yet that warrant a dedicated subtype. Add it here when a specific scenario
  emerges (e.g. a missing API key detected at dispatch time).
  """

  defmodule SystemError do
    @moduledoc "Webhook execution failure (HTTP error, API rejection, parse failure)."
    defexception [:message]
  end

  defmodule TimeoutError do
    @moduledoc "Async webhook await window expired without a Kaapi callback."
    defexception [:message]
  end

  defmodule Error do
    @moduledoc "General-purpose webhook failure not covered by the more specific types."
    defexception [:message]
  end
end
