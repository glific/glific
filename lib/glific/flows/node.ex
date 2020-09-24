defmodule Glific.Flows.Node do
  @moduledoc """
  The Node object which encapsulates one node in a given flow
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    Flows,
    Messages.Message
  }

  alias Glific.Flows.{
    Action,
    Exit,
    Flow,
    FlowContext,
    FlowCount,
    Router
  }

  @required_fields [:uuid, :actions, :exits]

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          flow_uuid: Ecto.UUID.t() | nil,
          flow: Flow.t() | nil,
          actions: [Action.t()] | [],
          exits: [Exit.t()] | [],
          router: Router.t() | nil
        }

  embedded_schema do
    field :uuid, Ecto.UUID

    field :flow_uuid, Ecto.UUID
    embeds_one :flow, Flow

    embeds_many :actions, Action
    embeds_many :exits, Exit
    embeds_one :router, Router
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), Flow.t()) :: {Node.t(), map()}
  def process(json, uuid_map, flow) do
    Flows.check_required_fields(json, @required_fields)

    node = %Node{
      uuid: json["uuid"],
      flow_uuid: flow.uuid
    }

    {actions, uuid_map} =
      Flows.build_flow_objects(
        json["actions"],
        uuid_map,
        &Action.process/3,
        node
      )

    node = Map.put(node, :actions, actions)

    {exits, uuid_map} =
      Flows.build_flow_objects(
        json["exits"],
        uuid_map,
        &Exit.process/3,
        node
      )

    node = Map.put(node, :exits, exits)

    {node, uuid_map} =
      if Map.has_key?(json, "router") do
        {router, uuid_map} = Router.process(json["router"], uuid_map, node)
        {Map.put(node, :router, router), uuid_map}
      else
        {node, uuid_map}
      end

    uuid_map = Map.put(uuid_map, node.uuid, {:node, node})
    {node, uuid_map}
  end

  @doc """
  Execute a node, given a message stream.
  Consume the message stream as processing occurs
  """
  @spec execute(Node.t(), FlowContext.t(), [Message.t()]) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]} | {:error, String.t()}
  def execute(node, context, messages) do
    # update the flow count
    FlowCount.upsert_flow_count(%{
      uuid: node.uuid,
      flow_uuid: node.flow_uuid,
      type: "node"
    })

    # if node has an action, execute the first action
    cond do
      # if both are non-empty, it means that we have either a
      #    * sub-flow option
      #    # callung a web hook
      !Enum.empty?(node.actions) && !is_nil(node.router) ->
        # need a better way to figure out if we should handle router or action
        # this is a hack for now
        if messages != [] and
             hd(messages).clean_body in ["completed", "expired", "success", "failure"],
           do: Router.execute(node.router, context, messages),
           else: Action.execute(hd(node.actions), context, messages)

      !Enum.empty?(node.actions) ->
        # we need to execute all the actions (nodes can have multiple actions)
        {:ok, context, messages} =
          Enum.reduce(
            node.actions,
            {:ok, context, messages},
            fn action, acc ->
              {:ok, context, messages} = acc
              Action.execute(action, context, messages)
            end
          )

        Exit.execute(hd(node.exits), context, messages)

      !is_nil(node.router) ->
        Router.execute(node.router, context, messages)

      true ->
        {:error, "Unsupported node type"}
    end
  end
end
