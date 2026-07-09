defmodule Glific.Flows.Webhooks.ErrorReporter do
  @moduledoc """
  Routes a classified sync-webhook failure to its AppSignal destination.

  A sync node names its own failure with an `ErrorType.t()` atom; this module maps the atom to a
  bucket and either reports an incident — `:config` → `flow_webhook_config_errors` (notifies
  support), `:system` → `flow_webhooks` (pages on-call) — or stays silent for a `:transient`
  blip (rate-monitored via the counter only). No classification happens here: the node already
  decided, this just routes and reports.

  See `plans/webhook-error-classification.md`.
  """

  alias Glific.Flows.Webhooks.{Errors, ErrorType}

  @type class :: :config | :system | :transient

  @doc "Map a class to its action: report under a namespace, or count-only (no incident)."
  @spec route(class()) :: {:report, String.t()} | :count
  def route(:system), do: {:report, "flow_webhooks"}
  def route(:config), do: {:report, "flow_webhook_config_errors"}
  def route(:transient), do: :count

  @doc """
  Report a typed sync failure. Maps `error_type` → class (an unrecognised atom fails safe to
  `:system`), then logs a `ConfigurationError`/`SystemError` under the routed namespace, or emits
  no incident for a transient blip. `tags` must include `:webhook_name`.
  """
  @spec report(ErrorType.t(), String.t(), map()) :: :ok
  def report(error_type, message, tags) do
    class = ErrorType.class(error_type) || :system

    case route(class) do
      {:report, namespace} ->
        tags[:webhook_name]
        |> exception_for(class)
        |> Glific.log_exception(
          namespace: namespace,
          tags: Map.merge(tags, %{reason: message, error_type: to_string(class)})
        )

      :count ->
        :ok
    end
  end

  @spec exception_for(String.t() | nil, class()) :: Exception.t()
  defp exception_for(webhook_name, :config),
    do: %Errors.ConfigurationError{message: "Webhook config_error from #{webhook_name}"}

  defp exception_for(webhook_name, _system),
    do: %Errors.SystemError{message: "Webhook system_error from #{webhook_name}"}
end
