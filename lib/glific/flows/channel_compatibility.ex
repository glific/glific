defmodule Glific.Flows.ChannelCompatibility do
  @moduledoc """
  Which flow nodes a channel can run, and the severity tier a mismatch reports at.

  `Action` and `Router` consult it while validating; `Flows.publish_flow/2` reads the tier off
  the errors they produce.
  """

  @blocking_category "Blocking"

  @unsupported_action_types %{"set_wa_group_field" => "Updating a WhatsApp group field"}

  @unsupported_webhooks %{"send_wa_group_poll" => "Sending a WhatsApp group poll"}

  @unsupported_router_operands %{"@contact.groups" => "Splitting by collection"}

  @template_label "Sending a WhatsApp template (HSM)"

  @doc """
  The category string that stops a publish rather than warning about it.
  """
  @spec blocking_category :: String.t()
  def blocking_category, do: @blocking_category

  @doc """
  Whether any of these validation errors must stop a publish.
  """
  @spec blocking_errors?(list()) :: boolean()
  def blocking_errors?(errors),
    do: Enum.any?(errors, &blocking_error?/1)

  @doc """
  Whether this flow runs on the web channel.
  """
  @spec web?(map()) :: boolean()
  def web?(%{channel: :web}), do: true
  def web?(_flow), do: false

  @doc """
  The reason this action cannot run on the web channel, or nil when it can.
  """
  @spec unsupported_action(map()) :: String.t() | nil
  def unsupported_action(%{type: type, is_template: true}) when type in ["send_msg"],
    do: @template_label

  def unsupported_action(%{type: "call_webhook", url: url}),
    do: Map.get(@unsupported_webhooks, url)

  def unsupported_action(%{type: type}),
    do: Map.get(@unsupported_action_types, type)

  @doc """
  The reason this router cannot run on the web channel, or nil when it can.
  """
  @spec unsupported_router(map()) :: String.t() | nil
  def unsupported_router(%{operand: operand}),
    do: Map.get(@unsupported_router_operands, operand)

  def unsupported_router(_router), do: nil

  @doc """
  A blocking validation error naming the node it came from.
  """
  @spec error(module(), String.t(), Ecto.UUID.t() | nil) :: tuple()
  def error(key, message, node_uuid), do: {key, message, @blocking_category, node_uuid}

  defp blocking_error?({_key, _message, @blocking_category}), do: true
  defp blocking_error?({_key, _message, @blocking_category, _node_uuid}), do: true
  defp blocking_error?(_error), do: false
end
