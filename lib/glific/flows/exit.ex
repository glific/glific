defmodule Glific.Flows.Exit do
  @moduledoc """
  The Exit object which encapsulates one exit in a given node.
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    Flows,
    Flows.FlowContext,
    Flows.Node,
    Messages.Message,
    Metrics,
    Repo
  }

  @required_fields [:uuid]

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | nil,
          destination_node_uuid: Ecto.UUID.t() | nil,
          destination_node: Node.t() | nil
        }

  embedded_schema do
    field :uuid, Ecto.UUID

    field :node_uuid, Ecto.UUID
    embeds_one :node, Node

    field :destination_node_uuid, Ecto.UUID
    embeds_one :destination_node, Node
  end

  @spec add_reverse(map(), Exit.t()) :: map()
  defp add_reverse(uuid_map, %{destination_node_uuid: nil}), do: uuid_map

  defp add_reverse(uuid_map, %{node_uuid: src, destination_node_uuid: dst}) do
    # we are only interested in one node leading to the destination, if there are multiple
    # we'll take the last update
    Map.put(
      uuid_map,
      {:reverse, dst},
      {:source, src}
    )
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), Node.t()) :: {Exit.t(), map()}
  def process(json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields)

    exit = %Exit{
      uuid: json["uuid"],
      node_uuid: node.uuid,
      destination_node_uuid: json["destination_uuid"]
    }

    uuid_map =
      uuid_map
      |> Map.put(exit.uuid, {:exit, exit})
      |> add_reverse(exit)

    {exit, uuid_map}
  end

  @doc """
  Validate a exit
  """
  @spec validate(Exit.t(), Keyword.t(), map()) :: Keyword.t()
  def validate(_exit, errors, _flow) do
    errors
  end

  @doc """
  Execute a exit, given a message stream.
  """
  @spec execute(atom() | Exit.t(), atom() | FlowContext.t(), [Message.t()]) ::
          {:ok, FlowContext.t() | nil, [Message.t()]} | {:error, String.t()}
  def execute(exit, context, messages) do
    context = Repo.preload(context, :flow)
    # update the flow count
    Metrics.bump(%{
      uuid: exit.uuid,
      destination_uuid: exit.destination_node_uuid,
      flow_uuid: context.flow_uuid,
      flow_id: context.flow.id,
      organization_id: context.organization_id,
      type: "exit",
      recent_message: get_recent_messages(context.recent_inbound)
    })

    cond do
      # Since we only support 3 nodes for WA groups rn, we are doing the flow ending
      # process seprately, eventually we can use the second clause for this too
      is_nil(exit.destination_node_uuid) and context.wa_group_id != nil ->
        event_label = "Marking flow as completed for WA group"
        FlowContext.mark_wa_flows_complete(event_label, context.wa_group_id)
        {:ok, nil, []}

      is_nil(exit.destination_node_uuid) ->
        FlowContext.reset_context(context)
        {:ok, nil, []}

      true ->
        {:ok, {:node, node}} = Map.fetch(context.uuid_map, exit.destination_node_uuid)

        Node.execute(
          node,
          FlowContext.set_node(context, node),
          messages
        )
    end
  end

  # get most recent message
  @spec get_recent_messages(nil | list()) :: map()
  defp get_recent_messages(recent_inbound) when recent_inbound in [nil, []], do: %{}
  defp get_recent_messages(recent_inbound), do: hd(recent_inbound)
end
