defmodule Glific.Flows.Webhooks.Errors do
  @moduledoc """
  Namespace alias for the flow-webhook exception modules.

  The actual `defexception` definitions live at
  `Glific.Flows.Webhook.{SystemError, TimeoutError, Error}` — AppSignal groups
  incidents by exception module name, so moving them would split historical
  incidents. We keep the legacy paths and just re-export them here so future
  code reads naturally.
  """

  alias Glific.Flows.Webhook

  @system_error Webhook.SystemError
  @timeout_error Webhook.TimeoutError
  @generic_error Webhook.Error

  @doc "Module alias for `Glific.Flows.Webhook.SystemError`."
  @spec system_error() :: module()
  def system_error, do: @system_error

  @doc "Module alias for `Glific.Flows.Webhook.TimeoutError`."
  @spec timeout_error() :: module()
  def timeout_error, do: @timeout_error

  @doc "Module alias for `Glific.Flows.Webhook.Error`."
  @spec generic_error() :: module()
  def generic_error, do: @generic_error
end
