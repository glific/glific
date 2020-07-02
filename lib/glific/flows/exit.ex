defmodule Glific.Flows.Exit do
  @moduledoc """
  The Exit object which encapsulates one exit in a given node.
  """

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.Flows.Node

  @required_fields [:node_id, :destination_node_id]
  @optional_fields []

  @type t() :: %__MODULE__{
    __meta__: Ecto.Schema.Metadata.t(),
    uuid: Ecto.UUID.t() | nil,
    node_id: Ecto.UUID.t() | nil,
    node: Node.t() | Ecto.Association.NotLoaded.t() | nil,
    destination_node_id: Ecto.UUID.t() | nil,
    destination_node: Node.t() | Ecto.Association.NotLoaded.t() | nil,
  }

  schema "exits" do
    belongs_to :node, Node
    belongs_to :destination_node, Node, foreign_key: :destination_node_id
  end


  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Node.t(), map()) :: Ecto.Changeset.t()
  def changeset(Node, attrs) do
    tag
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:node_id)
    |> foreign_key_constraint(:destination_node_id)
  end


end
