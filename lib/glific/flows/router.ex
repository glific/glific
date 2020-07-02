defmodule Glific.Flows.Router do
  @moduledoc """
  The Router object which encapsulates the router in a given node.
  """

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.Flows{
    Case,
    Category,
    Node
  }

  @required_fields [:node_id]
  @optional_fields []

  @type t() :: %__MODULE__{
    __meta__: Ecto.Schema.Metadata.t(),
    uuid: Ecto.UUID.t() | nil,
    node_id: Ecto.UUID.t() | nil,
  }

  schema "routers" do
    field :name, :string

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
