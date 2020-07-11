defmodule Glific.Flows.FlowContext do
  @moduledoc """
  When we are running a flow, we are running it in the context of a
  contact and/or a conversation (or other Glific data types). Let encapsulate
  this in a module and isolate the flow from the other aspects of Glific
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Contacts.Contact,
    Flows.Flow,
    Flows.Node
  }

  @required_fields [:contact_id, :flow_uuid, :uuid_map]
  @optional_fields [:node_uuid]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid_map: map() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          flow_uuid: Ecto.UUID.t() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | Ecto.Association.NotLoaded.t() | nil,
          parent_id: non_neg_integer | nil,
          parent: FlowContext.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "flow_contexts" do
    field :uuid_map, :map, virtual: true
    field :node_uuid, Ecto.UUID, virtual: true
    embeds_one :node, Node

    belongs_to :contact, Contact

    belongs_to :flow, Flow, foreign_key: :flow_uuid, references: :uuid, primary_key: false
    belongs_to :parent, FlowContext, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(FlowContext.t(), map()) :: Ecto.Changeset.t()
  def changeset(context, attrs) do
    context
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:flow_uuid)
    |> foreign_key_constraint(:node_uuid)
  end

  @spec get_node_uuid(Node.t() | nil) :: Ecto.UUID.t() | nil
  defp get_node_uuid(nil), do: nil
  defp get_node_uuid(node), do: node.uuid

  @doc """
  Set the new node for the context
  """
  @spec set_node(FlowContext.t(), Node.t() | nil) :: FlowContext.t()
  def set_node(context, node) do
    context
    |> Map.put(:node, node)
    |> Map.put(:node_uuid, get_node_uuid(node))
  end

  @doc """
  Execute one (or more) steps in a flow based on the message stream
  """
  @spec execute(FlowContext.t(), [String.t()]) ::
          {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def execute(context, messages) when messages == [],
    do: {:ok, context, []}

  def execute(%FlowContext{node: node} = _context, _messages) when is_nil(node),
    do: {:error, "We have finished the flow"}

  def execute(context, messages) do
    {:ok, context, messages} = Node.execute(context.node, context, messages)
    FlowContext.execute(context, messages)
  end
end
