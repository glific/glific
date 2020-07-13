defmodule Glific.Flows.FlowContext do
  @moduledoc """
  When we are running a flow, we are running it in the context of a
  contact and/or a conversation (or other Glific data types). Let encapsulate
  this in a module and isolate the flow from the other aspects of Glific
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Flows.Flow,
    Flows.Node,
    Repo
  }

  @required_fields [:contact_id, :flow_id, :uuid_map]
  @optional_fields [:node_uuid, :parent_id]

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid_map: map() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          flow_id: non_neg_integer | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          parent_id: non_neg_integer | nil,
          parent: FlowContext.t() | Ecto.Association.NotLoaded.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "flow_contexts" do
    field :uuid_map, :map, virtual: true
    field :node, :map, virtual: true

    field :node_uuid, Ecto.UUID

    belongs_to :contact, Contact
    belongs_to :flow, Flow
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
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Create a FlowContext
  """
  @spec create_flow_context(map()) :: {:ok, FlowContext.t()} | {:error, Ecto.Changeset.t()}
  def create_flow_context(attrs \\ %{}) do
    %FlowContext{}
    |> FlowContext.changeset(attrs)
    |> Repo.insert()
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
    # stash the old_context to update db
    old_context = context
    {:ok, context, messages} = Node.execute(context.node, context, messages)

    # we've modified the context, lets update it
    # we are ignoring the new context here, since we want to update
    # the old context with the values of the new context (ecto design)
    {:ok, _} =
      old_context
      |> FlowContext.changeset(%{node_uuid: context.node_uuid})
      |> Repo.update()

    {:ok, context, messages}
  end

  @doc """
  Start a new context, if there is an existing context, blow it away
  """
  @spec init_context(Flow.t(), non_neg_integer) :: FlowContext.t()
  def init_context(flow, contact_id) do
    query =
      from fc in FlowContext,
        where: fc.contact_id == ^contact_id

    # dont care about the return, since it would have deleted
    # either 0 or 1 entries
    Repo.delete_all(query)

    {:ok, context} = create_flow_context(%{
      contact_id: contact_id,
      flow_id: flow.id,
      uuid_map: flow.uuid_map
                                         })

    context
    |> Repo.preload(:contact)
    |> load_context(flow)
  end

  @doc """
  Check if there is an active context (i.e. with a non null, node_uuid for this contact)
  """
  @spec active_context(non_neg_integer) :: FlowContext.t() | nil
  def active_context(contact_id) do
    query =
      from fc in FlowContext,
        where: fc.contact_id == ^contact_id and not is_nil(fc.node_uuid)

    Repo.one(query)
    |> Repo.preload(:contact)
  end

  @doc """
  Load the context object, given a flow object and a contact. At some point,
  we'll get the genserver to cache this
  """
  @spec load_context(FlowContext.t(), Flow.t()) :: FlowContext.t()
  def load_context(context, flow) do
    {:ok, {:node, node}} = Map.fetch(flow.uuid_map, context.node_uuid)

    context
    |> Map.put(:uuid_map, flow.uuid_map)
    |> Map.put(:node, node)
  end

  @doc """
  Given an input string, consume the input and advance the state of the context
  """
  @spec step_forward(FlowContext.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def step_forward(context, body) do
    case FlowContext.execute(context, [body]) do
      {:ok, context, []} -> {:ok, context}
      {:error, error} -> {:error, error}
    end
  end
end
