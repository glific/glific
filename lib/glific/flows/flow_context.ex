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

  @required_fields [:contact_id, :flow_id, :flow_uuid, :uuid_map]
  @optional_fields [:node_uuid, :parent_id, :results, :wakeup_at, :completed_at]

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid_map: map() | nil,
          results: map() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          flow_id: non_neg_integer | nil,
          flow_uuid: Ecto.UUID.t() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          parent_id: non_neg_integer | nil,
          parent: FlowContext.t() | Ecto.Association.NotLoaded.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | nil,
          wakeup_at: :utc_datetime | nil,
          completed_at: :utc_datetime | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "flow_contexts" do
    field :uuid_map, :map, virtual: true
    field :node, :map, virtual: true

    field :results, :map, default: %{}

    field :node_uuid, Ecto.UUID
    field :flow_uuid, Ecto.UUID

    field :wakeup_at, :utc_datetime, default: nil
    field :completed_at, :utc_datetime, default: nil

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

  @doc false
  @spec update_flow_context(FlowContext.t(), map()) ::
          {:ok, FlowContext.t()} | {:error, Ecto.Changeset.t()}
  def update_flow_context(context, attrs) do
    context
    |> FlowContext.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Resets the context and sends control back to the parent context
  if one exists
  """
  @spec reset_context(FlowContext.t()) :: FlowContext.t() | nil
  def reset_context(context) do
    # we first update this entry with the completed at time
    {:ok, context} = FlowContext.update_flow_context(context, %{completed_at: DateTime.utc_now()})

    # check if context has a parent_id, if so, we need to
    # load that context and keep going
    if context.parent_id do
      # we load the parent context, and resume it with a message of "Completed"
      parent = active_context(context.contact_id)

      parent
      |> load_context(Flow.get_flow(parent.flow_uuid))
      |> step_forward("completed")
    end
  end

  @doc """
  Update the contact results state as we step through the flow
  """
  @spec update_results(FlowContext.t(), String.t(), String.t(), String.t()) :: FlowContext.t()
  def update_results(context, key, input, category) do
    results =
      if is_nil(context.results),
        do: %{},
        else: context.results

    results = Map.put(results, key, %{"input" => input, "category" => category})

    {:ok, context} =
      context
      |> FlowContext.changeset(%{results: results})
      |> Repo.update()

    context
  end

  @doc """
  Update the contact results with each element of the json map
  """
  @spec update_results(FlowContext.t(), String.t(), map()) :: FlowContext.t()
  def update_results(context, key, json) do

  end

  @doc """
  Set the new node for the context
  """
  @spec set_node(FlowContext.t(), Node.t()) :: FlowContext.t()
  def set_node(context, node) do
    {:ok, context} = update_flow_context(context, %{node_uuid: node.uuid})
    %{context | node: node}
  end

  @doc """
  Execute one (or more) steps in a flow based on the message stream
  """
  @spec execute(FlowContext.t(), [String.t()]) ::
          {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def execute(%FlowContext{node: node} = _context, _messages) when is_nil(node),
    do: {:error, "We have finished the flow"}

  def execute(context, messages) do
    Node.execute(context.node, context, messages)
  end

  @doc """
  Start a new context, if there is an existing context, blow it away
  """
  @spec init_context(Flow.t(), Contact.t(), non_neg_integer | nil) ::
          {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def init_context(flow, contact, parent_id \\ nil) do
    # set previous context only if we are not starting a sub flow
    if is_nil(parent_id) do
      now = DateTime.utc_now()

      FlowContext
      |> where([fc], fc.contact_id == ^contact.id)
      |> where([fc], is_nil(fc.completed_at))
      |> Repo.update_all(set: [completed_at: now, updated_at: now])
    end

    node = hd(flow.nodes)

    {:ok, context} =
      create_flow_context(%{
        contact_id: contact.id,
        parent_id: parent_id,
        node_uuid: node.uuid,
        flow_uuid: flow.uuid,
        node: node,
        results: %{},
        flow_id: flow.id,
        flow: flow,
        uuid_map: flow.uuid_map
      })

    context
    |> load_context(flow)
    |> Repo.preload(:contact)
    # lets do the first steps and start executing it till we need a message
    |> execute([])
  end

  @spec wakeup() :: [FlowContext.t()]
  @doc """
  Find all the contexts which need to be woken up and processed
  """
  def wakeup do
    FlowContext
    |> where([fc], fc.wakeup_at < ^DateTime.utc_now())
    |> where([fc], is_nil(fc.completed_at))
    |> Repo.all()
  end

  @doc """
  Check if there is an active context (i.e. with a non null, node_uuid for this contact)
  """
  @spec active_context(non_neg_integer) :: FlowContext.t() | nil
  def active_context(contact_id) do
    # need to fix this instead of assuming the highest id is the most
    # active context (or is that a wrong assumption). Maybe a context number? like
    # we do for other tables
    query =
      from fc in FlowContext,
        where:
          fc.contact_id == ^contact_id and
            not is_nil(fc.node_uuid) and
            is_nil(fc.completed_at),
        order_by: [desc: fc.id],
        limit: 1

    Repo.one(query) |> Repo.preload(:contact)
  end

  @doc """
  Load the context object, given a flow object and a contact. At some point,
  we'll get the genserver to cache this
  """
  @spec load_context(FlowContext.t(), Flow.t()) :: FlowContext.t()
  def load_context(context, flow) do
    {:ok, {:node, node}} = Map.fetch(flow.uuid_map, context.node_uuid)

    context
    |> Repo.preload(:contact)
    |> Map.put(:flow, flow)
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

  @doc """
  Retrieve the value from a results string
  """
  @spec get_result_value(FlowContext.t(), String.t()) :: String.t() | nil
  def get_result_value(context, value) do
    if String.starts_with?(value, "@results.") do
      parts = String.slice(value, 8..-1) |> String.split(".", trim: true)
      get_in(context.results, parts)
    else
      nil
    end
  end
end
