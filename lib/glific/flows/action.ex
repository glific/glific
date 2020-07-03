defmodule Glific.Flows.Action do
  @moduledoc """
  The Action object which encapsulates one action in a given node.
  """

  alias __MODULE__

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.Enums.FlowType

  alias Glific.Flows.{
    Flow,
    Node
  }

  @required_fields [:type, :node_uuid]
  @optional_fields [:text, :quick_replies, :flow_uuid]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid: Ecto.UUID.t() | nil,
          text: String.t() | nil,
          type: FlowType,
          quick_replies: [String.t()],
          enter_flow_uuid: Ecto.UUID.t() | nil,
          enter_flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "actions" do
    field :text, :string
    field :type, FlowType
    field :quick_replies, {:array, :string}, default: []

    belongs_to :node, Node, foreign_key: :node_uuid, references: :uuid, primary_key: true

    belongs_to :enter_flow, Flow,
      foreign_key: :enter_flow_uuid,
      references: :uuid,
      primary_key: true
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Action.t(), map()) :: Ecto.Changeset.t()
  def changeset(action, attrs) do
    action
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:node_uuid)
    |> foreign_key_constraint(:flow_uuid)
  end
end
