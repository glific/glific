defmodule Glific.Flows.Exit do
  @moduledoc """
  The Exit object which encapsulates one exit in a given node.
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Flows.{
    FlowContext,
    Node
  }

  @required_fields [:node_uuid, :destination_node_uuid]
  @optional_fields []

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
  @spec execute(Exit.t(), FlowContext.t(), [String.t()]) ::
          {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def execute(exit, context, message_stream) do
    if is_nil(exit.destination_node_uuid) do
      IO.puts("And we have reached the end of the help menu")
      {:ok, FlowContext.set_node(context, nil), []}
    else
      {:ok, {:node, node}} = Map.fetch(context.uuid_map, exit.destination_node_uuid)

      Node.execute(
        node,
        FlowContext.set_node(context, node),
        message_stream
      )
    end
  end
end
