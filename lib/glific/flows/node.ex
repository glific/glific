defmodule Glific.Flows.Node do
  @moduledoc """
  The Node object which encapsulates one node in a given flow
  """
  alias __MODULE__

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.Flows.{
    Action,
    Exit,
    Flow,
    Router
  }

  @required_fields [:flow_uuid]
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid: Ecto.UUID.t() | nil,
          flow_uuid: Ecto.UUID.t() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "nodes" do
    belongs_to :flow, Flow, foreign_key: :flow_uuid, references: :uuid, primary_key: true

    has_many :actions, Action
    has_many :exits, Exit
    has_one :router, Router
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
  @spec execute(Node.t(), map(), [String.t()]) :: any
  def execute(node, uuid_map, message_stream) do
    # if node has an action, execute the first action
    cond do
      !Enum.empty?(node.actions) ->
        Action.execute(hd(node.actions), uuid_map, message_stream)
        Exit.execute(hd(node.exits), uuid_map, message_stream)

      !is_nil(node.router) ->
        Router.execute(node.router, uuid_map, message_stream)

      true ->
        IO.puts("ERROR: We are not supposed to land here")
    end
  end
end
