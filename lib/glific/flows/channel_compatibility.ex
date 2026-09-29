defmodule Glific.Flows.ChannelCompatibility do
  @moduledoc """
  Which flow nodes a channel can run, and the severity tier a mismatch reports at.

  `Action` and `Node` consult it while validating. A mismatch is tagged `"Blocking"`, the
  category `Glific.Flows` refuses a publish on.
  """

  alias Glific.Flows.Flow

  @blocking_category "Blocking"

  @unsupported_action_types %{"set_wa_group_field" => "Updating a WhatsApp group field"}

  @unsupported_webhooks %{"send_wa_group_poll" => "Sending a WhatsApp group poll"}

  @unsupported_router_operands %{"@contact.groups" => "Splitting by collection"}

  @template_label "Sending a WhatsApp template (HSM)"

  @doc """
  Refuse the actions and router on this node that its flow's channel cannot run.
  """
  @spec check_node(list(), map(), map()) :: list()
  def check_node(errors, node, flow) do
    if web?(flow) do
      node.actions
      |> Enum.reduce(errors, &refuse(&2, unsupported_action(&1), node.uuid))
      |> check_router(node.router, node.uuid)
    else
      errors
    end
  end

  @doc """
  Refuse a sub-flow that runs on a channel the flow entering it does not.
  """
  @spec check_sub_flow(list(), map(), map(), Ecto.UUID.t() | nil) :: list()
  def check_sub_flow(errors, sub_flow, flow, node_uuid) do
    if web?(flow) and not web?(sub_flow),
      do:
        refuse(
          errors,
          ~s(Entering the sub-flow "#{sub_flow.name}", which runs on WhatsApp),
          node_uuid
        ),
      else: errors
  end

  @spec web?(map()) :: boolean()
  defp web?(%{channel: :web}), do: true
  defp web?(_flow), do: false

  @spec error(String.t(), Ecto.UUID.t() | nil) :: tuple()
  defp error(message, node_uuid), do: {Flow, message, @blocking_category, node_uuid}

  @spec check_router(list(), map() | nil, Ecto.UUID.t() | nil) :: list()
  defp check_router(errors, nil, _node_uuid), do: errors

  defp check_router(errors, router, node_uuid),
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
end
