defmodule Glific.Flows.Action do
  @moduledoc """
  The Action object which encapsulates one action in a given node.
  """

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.Enums.FlowTypeEnum
  alias Glific.Flows.{
    Flow,
    Node
  }

  @required_fields [:node_id]
  @optional_fields [:text]

  @type t() :: %__MODULE__{
    __meta__: Ecto.Schema.Metadata.t(),
    uuid: Ecto.UUID.t() | nil,

    text: String.t() | nil,
    type: FlowTypeEnum,
    quick_replies: [String.t],

    flow_id: Ecto.UUID.t() | nil,
    flow: Flow.t() | nil,

    node_id: Ecto.UUID.t() | nil,
    node: Node.t() | Ecto.Association.NotLoaded.t() | nil,
  }

  schema "actions" do
    field :text :string
    field :type FlowTypeEnum
    field :quick_replies, :string

    belongs_to :node, Node
    belongs_to :flow, Flow
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
    |> foreign_key_constraint(:flow_id)
  end


end
