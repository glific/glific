defmodule Glific.Flows.Exit do
  @moduledoc """
  The Exit object which encapsulates one exit in a given node.
  """
  alias __MODULE__

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.Flows.Node

  @required_fields [:node_uuid, :destination_node_uuid]
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid: Ecto.UUID.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | Ecto.Association.NotLoaded.t() | nil,
          destination_node_uuid: Ecto.UUID.t() | nil,
          destination_node: Node.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "exits" do
    belongs_to :node, Node, foreign_key: :node_uuid, references: :uuid, primary_key: true

    belongs_to :destination_node, Node,
      foreign_key: :destination_node_uuid,
      references: :uuid,
      primary_key: true
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Exit.t(), map()) :: Ecto.Changeset.t()
  def changeset(exit, attrs) do
    exit
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:node_uuid)
    |> foreign_key_constraint(:destination_node_uuid)
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), Node.t()) :: {Exit.t(), map()}
  def process(json, uuid_map, node) do
    exit = %Exit{
      uuid: json["uuid"],
      node_uuid: node.uuid,
      destination_node_uuid: json["destination_uuid"]
    }

    {exit, Map.put(uuid_map, exit.uuid, {:exit, exit})}
  end

  @doc """
  Execute a exit, given a message stream.
  """
  @spec execute(Exit.t, map(), [String.t]) :: any
  def execute(exit, uuid_map, message_stream) do
    if is_nil(exit.destination_node_uuid) do
      IO.puts("And we have reached the end of the help menu")
    else
      {:ok, {:node, node}} = Map.fetch(uuid_map, exit.destination_node_uuid)
      Node.execute(node, uuid_map, message_stream)
    end
  end

end
