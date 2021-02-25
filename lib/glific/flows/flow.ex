defmodule Glific.Flows.Flow do
  @moduledoc """
  The flow object which encapsulates the complete flow as emitted by
  by `https://github.com/nyaruka/floweditor`
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Enums.FlowType,
    Flows,
    Flows.FlowContext,
    Flows.FlowRevision,
    Flows.Localization,
    Flows.Node,
    Partners.Organization,
    Repo
  }

  @required_fields [:name, :uuid, :organization_id]
  @optional_fields [:flow_type, :keywords, :version_number, :uuid_map, :nodes, :ignore_keywords]

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          uuid: Ecto.UUID.t() | nil,
          uuid_map: map() | nil,
          keywords: [String.t()] | nil,
          ignore_keywords: boolean() | nil,
          flow_type: String.t() | nil,
          status: String.t(),
          definition: map() | nil,
          localization: Localization.t() | nil,
          nodes: [Node.t()] | nil,
          version_number: String.t() | nil,
          revisions: [FlowRevision.t()] | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "flows" do
    field :name, :string

    # this is the flow editor version number
    field :version_number, :string
    field :flow_type, FlowType
    field :uuid, Ecto.UUID

    field :uuid_map, :map, virtual: true
    field :nodes, :map, virtual: true
    field :localization, :map, virtual: true

    # This is the dynamic status that we use primarily during
    # flow execution. It tells us if we are using the draft version
    # or the published version of the flow
    field :status, :string, virtual: true, default: "published"

    field :keywords, {:array, :string}, default: []
    field :ignore_keywords, :boolean, default: false

    # we use this to store the latest definition and versionfrom flow_revisions for this flow
    field :definition, :map, virtual: true

    # this is the version of the flow revision
    field :version, :integer, virtual: true, default: 0

    belongs_to :organization, Organization

    has_many :revisions, FlowRevision

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Flow.t(), map()) :: Ecto.Changeset.t()
  def changeset(flow, attrs) do
    changeset =
      flow
      |> cast(attrs, @required_fields ++ @optional_fields)
      |> validate_required(@required_fields)
      |> unique_constraint([:name, :organization_id])
      |> update_change(:keywords, &update_keywords(&1))

    validate_keywords(changeset, get_change(changeset, :keywords))
  end

  @spec update_keywords(any()) :: list()
  defp update_keywords(keywords) when is_list(keywords),
    do: Enum.map(keywords, fn keyword -> String.downcase(keyword) end)

  defp update_keywords(_), do: []

  @doc """
  Changeset helper for keywords
  """
  @spec validate_keywords(Ecto.Changeset.t(), any()) :: Ecto.Changeset.t()
  def validate_keywords(changeset, nil), do: validate_keywords(changeset, [])

  def validate_keywords(changeset, keywords) do
    id = get_field(changeset, :id)
    organization_id = get_field(changeset, :organization_id)

    query =
      if is_nil(id),
        do: Flows.Flow,
        else: Flows.Flow |> where([f], f.id != ^id and f.organization_id == ^organization_id)

    flow_keyword_list = get_other_flow_keyword_list(query)
    keywords_list = Map.keys(flow_keyword_list)

    existing_keywords =
      keywords
      |> Enum.filter(fn keyword ->
        if keyword in keywords_list, do: Glific.string_clean(keyword)
      end)

    if existing_keywords != [] do
      changeset
      |> add_error(
        :keywords,
        create_keywords_error_message(existing_keywords, flow_keyword_list)
      )
    else
      changeset
    end
  end

  @spec create_keywords_error_message([], map()) :: String.t()
  defp create_keywords_error_message(existing_keywords, flow_keyword_list) do
    existing_keywords_string =
      existing_keywords
      |> Enum.map(fn keyword ->
        "The keyword `#{keyword}` was already used in the `#{flow_keyword_list[keyword]}` Flow"
      end)
      |> Enum.join(", ")

    "#{existing_keywords_string}."
  end

  @spec get_other_flow_keyword_list(Ecto.Query.t()) :: map()
  defp get_other_flow_keyword_list(query),
    do:
      query
      |> select([f], %{keywords: f.keywords, name: f.name})
      |> Repo.all()
      |> Enum.reduce(%{}, fn flow, acc ->
        flow.keywords
        |> Enum.reduce(%{}, fn keyword, acc_2 ->
          Map.put(acc_2, Glific.string_clean(keyword), flow.name)
        end)
        |> Map.merge(acc)
      end)

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), Flow.t()) :: Flow.t()
  def process(json, flow) do
    {nodes, uuid_map} =
      Enum.reduce(
        json["nodes"],
        {[], %{}},
        fn node_json, acc ->
          {node, uuid_map} = Node.process(node_json, elem(acc, 1), flow)
          {[node | elem(acc, 0)], uuid_map}
        end
      )

    flow
    |> Map.put(:uuid_map, uuid_map)
    |> Map.put(:localization, Localization.process(json["localization"]))
    |> Map.put(:nodes, Enum.reverse(nodes))
  end

  @doc """
  Build the context so we can execute the flow
  """
  @spec context(Flow.t(), Contact.t()) :: {:ok, FlowContext.t()} | {:error, String.t()}
  def context(%Flow{nodes: nodes}, _contact) when nodes == [],
    do: {:error, "An empty flow cannot have a context or be executed"}

  def context(flow, contact) do
    # get the first node
    node = hd(flow.nodes)

    attrs = %{
      contact: contact,
      contact_id: contact.id,
      flow_id: flow.id,
      uuid_map: flow.uuid_map,
      node_uuid: node.uuid
    }

    {:ok, context} =
      %FlowContext{}
      |> FlowContext.changeset(attrs)
      |> Repo.insert()

    context =
      context
      |> Repo.preload(:contact)
      |> Map.put(:node, node)

    {:ok, context}
  end

  # in some cases floweditor wraps the json under a "definition" key
  @spec clean_definition(map()) :: map()
  defp clean_definition(json),
    do: elem(Map.pop(json, "definition", json), 0) |> Map.delete("_ui")

  @doc """
  load the latest revision, specifically json definition from the
  flow_revision table. We return the clean definition back
  """
  @spec get_latest_definition(integer) :: map()
  def get_latest_definition(flow_id) do
    query =
      from fr in FlowRevision,
        where: fr.revision_number == 0 and fr.flow_id == ^flow_id,
        select: fr.definition

    Repo.one(query)
    # lets get rid of stuff we don't use, specfically the definition and
    # UI layout of the flow
    |> clean_definition()
  end

  @doc """
  Create a subflow of an existing flow
  """
  @spec start_sub_flow(FlowContext.t(), Ecto.UUID.t()) ::
          {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def start_sub_flow(context, uuid) do
    # we might want to put the current one under some sort of pause status
    flow = get_flow(context.flow.organization_id, uuid, context.status)

    FlowContext.init_context(flow, context.contact, context.status,
      parent_id: context.id,
      delay: context.delay
    )
  end

  @doc """
  Return a flow for a specific uuid. Cache is not present in cache
  """
  @spec get_flow(non_neg_integer, Ecto.UUID.t(), String.t()) :: map()
  def get_flow(organization_id, uuid, status) do
    {:ok, flow} = Flows.get_cached_flow(organization_id, {:flow_uuid, uuid, status})

    flow
  end

  @doc """
  Helper function to load a active flow from the database and build an object
  """
  @spec get_loaded_flow(non_neg_integer, String.t(), map()) :: map()
  def get_loaded_flow(organization_id, status, args) do
    query =
      from f in Flow,
        join: fr in assoc(f, :revisions),
        where: f.organization_id == ^organization_id,
        where: fr.flow_id == f.id,
        select: %Flow{
          id: f.id,
          name: f.name,
          uuid: f.uuid,
          keywords: f.keywords,
          ignore_keywords: f.ignore_keywords,
          organization_id: f.organization_id,
          definition: fr.definition,
          version: fr.version
        }

    flow =
      query
      |> status_clause(status)
      |> args_clause(args)
      |> Repo.one!()
      |> Map.put(:status, status)

    flow.definition
    |> clean_definition()
    |> process(flow)
  end

  @doc """
  Validate a flow and ensures the flow  is valid with our internal rule-set
  """
  @spec validate_flow(non_neg_integer, String.t(), map()) :: Keyword.t()
  def validate_flow(organization_id, status, args) do
    organization_id
    |> get_loaded_flow(status, args)
    |> validate_flow()
  end

  @spec validate_flow(map()) :: Keyword.t()
  defp validate_flow(flow) do
    errors = []

    flow.nodes
    |> Enum.reduce(
      errors,
      &Node.validate(&1, &2, flow)
    )
    |> dangling_nodes(flow)
    |> missing_flow_context_nodes(flow)
  end

  @spec flow_objects(map(), atom()) :: MapSet.t()
  defp flow_objects(flow, type) do
    flow.uuid_map
    |> Enum.filter(fn {_k, v} -> elem(v, 0) == type end)
    |> Enum.map(fn {k, _v} -> k end)
    |> MapSet.new()
  end

  @spec dangling_nodes(Keyword.t(), map()) :: Keyword.t()
  defp dangling_nodes(errors, flow) do
    all_nodes = flow_objects(flow, :node)
    all_exits = flow_objects(flow, :exit)

    # the first node is always reachable
    reachable_nodes =
      all_exits
      |> Enum.reduce(
        MapSet.new([hd(flow.nodes).uuid]),
        fn e, acc ->
          {:exit, exit} = flow.uuid_map[e]
          MapSet.put(acc, exit.destination_node_uuid)
        end
      )
      |> MapSet.delete(nil)

    dangling = MapSet.difference(all_nodes, reachable_nodes)

    if MapSet.size(dangling) == 0,
      do: errors,
      else: [dangling: "Your flow has dangling nodes"] ++ errors
  end

  @spec missing_flow_context_nodes(Keyword.t(), map()) :: Keyword.t()
  defp missing_flow_context_nodes(errors, flow) do
    all_nodes = flow_objects(flow, :node)

    flow_context_nodes =
      FlowContext
      |> where([fc], fc.flow_id == ^flow.id and is_nil(fc.completed_at))
      |> select([fc], fc.node_uuid)
      |> distinct(true)
      |> Repo.all()
      |> MapSet.new()

    if MapSet.subset?(flow_context_nodes, all_nodes),
      do: errors,
      else: [flowContext: "Some of your users in the flow have their node deleted"] ++ errors
  end

  # add the appropriate where clause as needed
  @spec args_clause(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp args_clause(query, %{id: id}),
    do: query |> where([f, _fr], f.id == ^id)

  defp args_clause(query, %{uuid: uuid}),
    do: query |> where([f, _fr], f.uuid == ^uuid)

  defp args_clause(query, %{keyword: keyword}),
    do: query |> where([f, _fr], ^keyword in f.keywords)

  defp args_clause(query, _args), do: query

  defp status_clause(query, "published" = status),
    do: query |> where([_f, fr], fr.status == ^status)

  defp status_clause(query, "draft"),
    do: query |> where([_f, fr], fr.revision_number == 0)
end
