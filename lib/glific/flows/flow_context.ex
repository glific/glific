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
    Flows,
    Flows.Flow,
    Flows.FlowResult,
    Flows.Node,
    Messages,
    Messages.Message,
    Partners.Organization,
    Repo
  }

  @required_fields [:contact_id, :flow_id, :flow_uuid, :status, :organization_id]
  @optional_fields [
    :node_uuid,
    :parent_id,
    :results,
    :wakeup_at,
    :completed_at,
    :delay,
    :uuid_map,
    :recent_inbound,
    :recent_outbound
  ]

  # we store one more than the number of messages specified here
  @max_message_len 9

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid_map: map() | nil,
          results: map() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          last_message: Message.t() | nil,
          flow_id: non_neg_integer | nil,
          flow_uuid: Ecto.UUID.t() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          status: String.t() | nil,
          parent_id: non_neg_integer | nil,
          parent: FlowContext.t() | Ecto.Association.NotLoaded.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | nil,
          delay: integer,
          recent_inbound: [map()] | [],
          recent_outbound: [map()] | [],
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

    field :status, :string, default: "published"

    field :wakeup_at, :utc_datetime, default: nil
    field :completed_at, :utc_datetime, default: nil

    field :delay, :integer, default: 0, virtual: true

    field :recent_inbound, {:array, :map}, default: []
    field :recent_outbound, {:array, :map}, default: []

    field :last_message, :map, virtual: true

    belongs_to :contact, Contact
    belongs_to :flow, Flow
    belongs_to :organization, Organization
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
      parent = active_context(context.contact_id, context.parent_id)

      parent
      |> load_context(
        Flow.get_flow(context.flow.organization_id, parent.flow_uuid, context.status)
      )
      |> step_forward(Messages.create_temp_message(context.flow.organization_id, "completed"))
    end
  end

  @doc """
  Update the recent_* state as we consume or send a message
  """
  @spec update_recent(FlowContext.t(), String.t(), atom()) :: FlowContext.t()
  def update_recent(context, body, type) do
    now = DateTime.utc_now()

    # since we are storing in DB and want to avoid hassle of atom <-> string conversion
    # we'll always use strings as keys
    messages =
      [%{"message" => body, "date" => now} | Map.get(context, type)]
      |> Enum.slice(0..@max_message_len)

    # since we have recd a message, we also ensure that we are not going to be woken
    # up by a timer if present.
    {:ok, context} = update_flow_context(context, %{type => messages, wakeup_at: nil})
    context
  end

  @doc """
  Update the contact results state as we step through the flow
  """
  @spec update_results(FlowContext.t(), String.t(), String.t() | map(), String.t()) ::
          FlowContext.t()
  def update_results(context, key, input, category) do
    results =
      if is_nil(context.results),
        do: %{},
        else: context.results

    results = Map.put(results, key, %{"input" => input, "category" => category})
    {:ok, context} = update_flow_context(context, %{results: results})

    {:ok, _flow_result} =
      FlowResult.upsert_flow_result(%{
        results: results,
        contact_id: context.contact_id,
        flow_id: context.flow_id,
        flow_version: context.flow.version,
        flow_uuid: context.flow_uuid,
        organization_id: context.contact.organization_id
      })

    context
  end

  @doc """
  Update the contact results with each element of the json map
  """
  @spec update_results(FlowContext.t(), String.t(), map()) :: FlowContext.t()
  def update_results(context, key, json) do
    json
    |> Enum.reduce(
      context,
      fn {k, v}, context ->
        update_results(context, key <> "_" <> k, v, key)
      end
    )
    # also add the entire json object in case folks want to access that
    |> update_results(key, json, key)
  end

  @doc """
  Count the number of times we have sent the same message in the recent past
  """
  @spec match_outbound(FlowContext.t(), Ecto.UUID.t(), integer) :: integer
  def match_outbound(context, uuid, go_back \\ 6) do
    since = Glific.go_back_time(go_back)

    Enum.filter(
      context.recent_outbound,
      fn item ->
        # sometime we get this from memory, and its not retrived from DB
        # in which case its already in a valid date format
        date =
          if is_binary(item["date"]),
            do:
              (
                {:ok, date, _} = DateTime.from_iso8601(item["date"])
                date
              ),
            else: item["date"]

        item["message"] == uuid and DateTime.compare(date, since) in [:gt, :eq]
      end
    )
    |> length()
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
  @spec execute(FlowContext.t(), [Message.t()]) ::
          {:ok, FlowContext.t(), [Message.t()]} | {:error, String.t()}
  def execute(%FlowContext{node: node} = _context, _messages) when is_nil(node),
    do: {:error, "We have finished the flow"}

  def execute(context, messages) do
    case Node.execute(context.node, context, messages) do
      {:ok, context, []} -> {:ok, context, []}
      {:ok, context, messages} -> Node.execute(context.node, context, messages)
      others -> others
    end
  end

  @doc """
  Start a new context, if there is an existing context, blow it away
  """
  @spec init_context(Flow.t(), Contact.t(), String.t(), Keyword.t() | []) ::
          {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def init_context(flow, contact, status, opts \\ []) do
    parent_id = Keyword.get(opts, :parent_id)
    current_delay = Keyword.get(opts, :delay, 0)

    # set all previous context to be completed if we are not starting a sub flow
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
        status: status,
        node: node,
        results: %{},
        flow_id: flow.id,
        flow: flow,
        organization_id: flow.organization_id,
        uuid_map: flow.uuid_map,
        delay: current_delay
      })

    context
    |> load_context(flow)
    |> Repo.preload(:contact)
    # lets do the first steps and start executing it till we need a message
    |> execute([])
  end

  @doc """
  Check if there is an active context (i.e. with a non null, node_uuid for this contact)
  """
  @spec active_context(non_neg_integer, non_neg_integer | nil) :: FlowContext.t() | nil
  def active_context(contact_id, parent_id \\ nil) do
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

    query =
      if parent_id,
        do: query |> where([fc], fc.id == ^parent_id),
        else: query

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
  @spec step_forward(FlowContext.t(), Message.t()) :: {:ok, map()} | {:error, String.t()}
  def step_forward(context, message) do
    case FlowContext.execute(context, [message]) do
      {:ok, context, []} -> {:ok, context}
      {:error, error} -> {:error, error}
    end
  end

  @spec wakeup_flows() :: :ok
  @doc """
  Find all the contexts which need to be woken up and processed
  """
  def wakeup_flows do
    FlowContext
    |> where([fc], fc.wakeup_at < ^DateTime.utc_now())
    |> where([fc], is_nil(fc.completed_at))
    |> preload(:flow)
    |> Repo.all(skip_organization_id: true)
    |> Enum.each(&wakeup_one(&1))

    :ok
  end

  @doc """
  Process one context at a time that is ready to be woken
  """
  @spec wakeup_one(FlowContext.t()) ::
          {:ok, FlowContext.t() | nil, [String.t()]} | {:error, String.t()}
  def wakeup_one(context) do
    # update the context woken up time as soon as possible to avoid someone else
    # grabbing this context
    {:ok, context} = FlowContext.update_flow_context(context, %{wakeup_at: nil})

    {:ok, flow} =
      Flows.get_cached_flow(
        context.flow.organization_id,
        {:flow_uuid, context.flow_uuid, context.status},
        %{uuid: context.flow_uuid}
      )

    {:ok, context} =
      context
      |> FlowContext.load_context(flow)
      |> FlowContext.step_forward(
        Messages.create_temp_message(context.flow.organization_id, "No Response")
      )

    {:ok, context, []}
  end

  @doc """
  Retrieve the value from a results string
  """
  @spec get_result_value(FlowContext.t(), String.t()) :: String.t() | nil
  def get_result_value(context, value) when binary_part(value, 0, 9) == "@results." do
    parts = String.slice(value, 8..-1) |> String.split(".", trim: true)
    get_in(context.results, parts)
  end

  def get_result_value(_context, value), do: value

  @doc """
  Delete all the contexts which are completed before two days
  """
  @spec delete_completed_flow_contexts() :: :ok
  def delete_completed_flow_contexts do
    back_date = DateTime.utc_now() |> DateTime.add(-2 * 24 * 60 * 60, :second)

    FlowContext
    |> where([fc], fc.completed_at < ^back_date)
    |> Repo.delete_all(skip_organization_id: true)

    :ok
  end

  @doc """
  Delete all the contexts which are older than 30 days
  """
  @spec delete_old_flow_contexts() :: :ok
  def delete_old_flow_contexts do
    last_month_date = DateTime.utc_now() |> DateTime.add(-30 * 24 * 60 * 60, :second)

    FlowContext
    |> where([fc], fc.inserted_at < ^last_month_date)
    |> Repo.delete_all(skip_organization_id: true)

    :ok
  end
end
