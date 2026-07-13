defmodule Glific.Flows.Webhooks.ErrorReporter do
  @moduledoc """
  Routes a self-classified sync-webhook failure to AppSignal: `:config` →
  `flow_webhook_config_errors` (notifies support), `:system` → `flow_webhooks` (pages on-call).
  The node owns the verdict; this only routes and reports. The specific `error_type` atom is
  tagged as-is so incidents stay filterable by cause within a bucket. See
  `plans/webhook-error-classification.md`.
  """

  alias Glific.Flows.Webhooks.{Errors, ErrorType}

  @type class :: :config | :system

  @spec report(ErrorType.t(), String.t(), map()) :: :ok
  def report(error_type, message, tags) do
    class = ErrorType.class(error_type) || :system

    tags[:webhook_name]
    |> exception_for(class)
    |> Glific.log_exception(
      namespace: namespace(class),
      tags: Map.merge(tags, %{reason: message, error_type: to_string(error_type)})
    )
  end

  @spec namespace(class()) :: String.t()
  defp namespace(:system), do: "flow_webhooks"
  defp namespace(:config), do: "flow_webhook_config_errors"

  @spec exception_for(String.t() | nil, class()) :: Exception.t()
  defp exception_for(webhook_name, :config),
    do: %Errors.ConfigurationError{message: "Webhook config_error from #{webhook_name}"}

  defp exception_for(webhook_name, _system),
    do: %Errors.SystemError{message: "Webhook system_error from #{webhook_name}"}
end
