defmodule Glific.Flows.Webhooks.Errors do
  @moduledoc """
  Exception types for the `Glific.Flows.Webhooks` subsystem.

  These are independent of the legacy `Glific.Flows.Webhook.{Error,SystemError,TimeoutError}`
  exception modules. New code in the `Webhooks` namespace raises and reports these types;
  the old single-module `Webhook` worker continues to use its own exception types.

  Three exception classes mirror the failure modes of the webhook execution pipeline:

  - `SystemError` — the webhook call itself failed (HTTP error, API rejection, parse
    failure). Raised or constructed in `Instrumentation.around/3`.
  - `TimeoutError` — an async webhook's await window expired without a callback.
    Raised in `Instrumentation.report_timeout/1`.
  - `Error` — general-purpose; for failures that don't fit the above categories.

  - `ConfigurationError` — NGO / flow-author misconfiguration (missing creds, bad JSON body,
    unrecognised webhook function). Routed to the `flow_webhook_config_errors` namespace so it
    notifies support instead of paging on-call.
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

  defmodule ConfigurationError do
    @moduledoc """
    Webhook failure caused by NGO / flow-author misconfiguration (missing creds, bad JSON body,
    unrecognised webhook function, unresolved template variable). Routed to a separate AppSignal
    namespace (`flow_webhook_config_errors`) so it notifies support instead of paging on-call.
    """
    defexception [:message]
  end
end
