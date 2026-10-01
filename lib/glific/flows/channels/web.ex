defmodule Glific.Flows.Channels.Web do
  @moduledoc """
  The work a web flow cannot run.

  The web channel has no BSP behind it, so anything that reaches WhatsApp infrastructure — a
  template, a WhatsApp group, a collection split — has nowhere to go and is refused at publish.
  """

  @behaviour Glific.Flows.Channels.Behaviour

  alias Glific.Flows.Flow

  @unsupported_action_types %{"set_wa_group_field" => "Updating a WhatsApp group field"}

  @unsupported_webhooks %{"send_wa_group_poll" => "Sending a WhatsApp group poll"}

  @unsupported_router_operands %{"@contact.groups" => "Splitting by collection"}

  @template_label "Sending a WhatsApp template (HSM)"

  @doc """
  Refuses the actions and router on this node that the web channel cannot run.
  """
  @impl true
  @spec validate_node(map(), list()) :: list()
  def validate_node(node, errors) do
    node.actions
    |> Enum.reduce(errors, &refuse(&2, unsupported_action(&1), node.uuid))
    |> validate_router(node.router, node.uuid)
  end

  @doc """
  Refuses a sub-flow that does not itself run on the web channel.
  """
  @impl true
  @spec validate_sub_flow(map(), list(), Ecto.UUID.t() | nil) :: list()
  def validate_sub_flow(%{channel: :web}, errors, _node_uuid), do: errors

  def validate_sub_flow(sub_flow, errors, node_uuid),
    do:
      refuse(
        errors,
        ~s(Entering the sub-flow "#{sub_flow.name}", which runs on WhatsApp),
        node_uuid
      )

  @spec validate_router(list(), map() | nil, Ecto.UUID.t() | nil) :: list()
  defp validate_router(errors, nil, _node_uuid), do: errors

  defp validate_router(errors, router, node_uuid),
    do: refuse(errors, unsupported_router(router), node_uuid)

  @spec refuse(list(), String.t() | nil, Ecto.UUID.t() | nil) :: list()
  defp refuse(errors, nil, _node_uuid), do: errors

  defp refuse(errors, message, node_uuid),
    do: [{:channel, Flow, message, node_uuid} | errors]

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
