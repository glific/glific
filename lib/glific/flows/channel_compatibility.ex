defmodule Glific.Flows.ChannelCompatibility do
  @moduledoc """
  Which flow nodes a channel can run, and the severity tier a mismatch reports at.

  `Action` and `Router` consult it while validating; `Flows.publish_flow/2` reads the tier off
  the errors they produce.
  """

  alias Glific.Flows.Flow

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
  Refuse the actions and router on this node that its flow's channel cannot run.
  """
  @spec node_errors(list(), map(), map()) :: list()
  def node_errors(errors, node, flow) do
    if web?(flow) do
      node.actions
      |> Enum.reduce(errors, &refuse(&2, unsupported_action(&1), node.uuid))
      |> router_errors(node.router, node.uuid)
    else
      errors
    end
  end

  @doc """
  A blocking validation error naming the node it came from.
  """
  @spec error(String.t(), Ecto.UUID.t() | nil) :: tuple()
  def error(message, node_uuid), do: {Flow, message, @blocking_category, node_uuid}

  @spec router_errors(list(), map() | nil, Ecto.UUID.t() | nil) :: list()
  defp router_errors(errors, nil, _node_uuid), do: errors

  defp router_errors(errors, router, node_uuid),
    do: refuse(errors, unsupported_router(router), node_uuid)

  @spec refuse(list(), String.t() | nil, Ecto.UUID.t() | nil) :: list()
  defp refuse(errors, nil, _node_uuid), do: errors
  defp refuse(errors, message, node_uuid), do: [error(message, node_uuid) | errors]

  @spec unsupported_action(map()) :: String.t() | nil
  defp unsupported_action(%{type: type, is_template: true}) when type in ["send_msg"],
    do: @template_label

  defp unsupported_action(%{type: "call_webhook", url: url}),
    do: Map.get(@unsupported_webhooks, url)

  defp unsupported_action(%{type: type}),
    do: Map.get(@unsupported_action_types, type)

  @spec unsupported_router(map()) :: String.t() | nil
  defp unsupported_router(%{operand: operand}),
    do: Map.get(@unsupported_router_operands, operand)

  defp blocking_error?({_key, _message, @blocking_category}), do: true
  defp blocking_error?({_key, _message, @blocking_category, _node_uuid}), do: true
  defp blocking_error?(_error), do: false
end
