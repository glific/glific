defmodule Glific.Flows.Node do
  @moduledoc """
  The Node object which encapsulates one node in a given flow
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Flows.{
    Action,
    Exit,
    Flow,
    FlowContext,
    Router
  }

  @required_fields [:flow_uuid]
  @optional_fields []

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
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Node.t(), map()) :: Ecto.Changeset.t()
  def changeset(node, attrs) do
    node
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:flow_uuid)
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), Flow.t()) :: {Node.t(), map()}
  def process(json, uuid_map, flow) do
    node = %Node{
      uuid: json["uuid"],
      flow_uuid: flow.uuid
    }

    {actions, uuid_map} =
      Enum.reduce(
        json["actions"],
        {[], uuid_map},
        fn action_json, acc ->
          {action, uuid_map} = Action.process(action_json, elem(acc, 1), node)
          {[action | elem(acc, 0)], uuid_map}
        end
      )

    node = Map.put(node, :actions, Enum.reverse(actions))

    {exits, uuid_map} =
      Enum.reduce(
        json["exits"],
        {[], uuid_map},
        fn exit_json, acc ->
          {exit, uuid_map} = Exit.process(exit_json, elem(acc, 1), node)
          {[exit | elem(acc, 0)], uuid_map}
        end
      )

    node = Map.put(node, :exits, Enum.reverse(exits))

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
  @spec execute(Node.t(), FlowContext.t(), [String.t()]) ::
          {:ok | :wait, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def execute(node, context, message_stream) do
    # if node has an action, execute the first action
    cond do
      # if both are non-empty, it means that we have a sub-flow option going on
      # thats our understanding for now
      !Enum.empty?(node.actions) && !is_nil(node.router) ->
        # need a better way to figure out if we should handle router or action
        # this is a hack for now
        if message_stream != [] and hd(message_stream) in ["completed", "expired"],
          do: Router.execute(node.router, context, message_stream),
          else: Action.execute(hd(node.actions), context, message_stream)

      !Enum.empty?(node.actions) ->
        # we need to execute all the actions (nodes can have multiple actions)
                _ = Enum.map(
          node.actions,
          fn action ->
            {:ok, _context, _message_stream} = Action.execute(action, context, message_stream)
          end
        )

        Exit.execute(hd(node.exits), context, message_stream)

      !is_nil(node.router) ->
        Router.execute(node.router, context, message_stream)

      true ->
        {:error, "Unsupported node type"}
    end
  end
end
