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
    AccessControl.Role,
    Contacts.Contact,
    Enums.FlowType,
    Flows,
    Flows.Action,
    Flows.FlowContext,
    Flows.FlowRevision,
    Flows.Localization,
    Flows.Node,
    Partners.Organization,
    Repo,
    Settings.Language,
    Tags.Tag
  }

  @required_fields [:name, :uuid, :organization_id]
  @optional_fields [
    :flow_type,
    :keywords,
    :version_number,
    :uuid_map,
    :nodes,
    :ignore_keywords,
    :is_active,
    :is_background,
    :is_pinned,
    :respond_other,
    :respond_no_response,
    :tag_id,
    :description
  ]

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          uuid: Ecto.UUID.t() | nil,
          uuid_map: map() | nil,
          keywords: [String.t()] | nil,
          ignore_keywords: boolean() | nil,
          is_active: boolean() | nil,
          is_background: boolean() | nil,
          is_pinned: boolean() | nil,
          respond_other: boolean() | nil,
          respond_no_response: boolean() | nil,
          flow_type: String.t() | nil,
          status: String.t(),
          definition: map() | nil,
          localization: Localization.t() | nil,
          start_node: Node.t() | nil,
          nodes: [Node.t()] | nil,
          version_number: String.t() | nil,
          revisions: [FlowRevision.t()] | Ecto.Association.NotLoaded.t() | nil,
          tag_id: non_neg_integer | nil,
          tag: Tag.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil,
          description: String.t() | nil
        }

  schema "flows" do
    field(:name, :string)
    field(:description, :string)

    # this is the flow editor version number
    field(:version_number, :string)
    field(:flow_type, FlowType)
    field(:uuid, Ecto.UUID)

    field(:uuid_map, :map, virtual: true)
    field(:start_node, :map, virtual: true)
    field(:nodes, :map, virtual: true)
    field(:localization, :map, virtual: true)
    field(:last_published_at, :utc_datetime, virtual: true)
    field(:last_changed_at, :utc_datetime, virtual: true)

    # This is the dynamic status that we use primarily during
    # flow execution. It tells us if we are using the draft version
    # or the published version of the flow
    field(:status, :string, virtual: true, default: "published")

    field(:keywords, {:array, :string}, default: [])
    field(:ignore_keywords, :boolean, default: false)
    field(:is_active, :boolean, default: true)
    field(:is_background, :boolean, default: false)
    field(:is_pinned, :boolean, default: false)
    field(:respond_other, :boolean, default: false)
    field(:respond_no_response, :boolean, default: false)
    # we use this to store the latest definition and version from flow_revisions for this flow
    field(:definition, :map, virtual: true)

    # this is the version of the flow revision
    field(:version, :integer, virtual: true, default: 0)

    belongs_to(:organization, Organization)
    belongs_to(:tag, Tag)
    has_many(:revisions, FlowRevision)
    many_to_many(:roles, Role, join_through: "flow_roles", on_replace: :delete)

    timestamps(type: :utc_datetime_usec)
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
      |> unique_constraint([:name, :organization_id],
        message: "Sorry, the flow name already exists."
      )
      |> unique_constraint([:uuid, :organization_id])
      |> foreign_key_constraint(:tag_id)
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
      |> Enum.map_join(", ", fn keyword ->
        "The keyword `#{keyword}` was already used in the `#{flow_keyword_list[keyword]}` Flow"
      end)

    # this should be combined with the above pipe, leaving for now since
    # i'm just cleaning up credo errors
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
  Process a json structure from flow editor to the Glific data types. While we are doing
  this we also fix the map, if the variables to resolve Other/No Response is true
  """
  @spec process(map(), Flow.t(), Ecto.UUID.t()) :: Flow.t()
  def process(json, flow, start_node_uuid) do
    {nodes, uuid_map} =
      Enum.reduce(
        json["nodes"],
        {[], %{}},
        fn node_json, acc ->
          {node, uuid_map} = Node.process(node_json, elem(acc, 1), flow)
          {[node | elem(acc, 0)], uuid_map}
        end
      )

    {nodes, uuid_map} = fix_nodes(nodes, uuid_map, flow)
    {:node, start_node} = Map.get(uuid_map, start_node_uuid)

    flow
    |> Map.put(:uuid_map, uuid_map)
    |> Map.put(:localization, Localization.process(json["localization"]))
    |> Map.put(:nodes, nodes)
    |> Map.put(:start_node, start_node)
  end

  @spec fix_nodes(Node.t(), map(), Flow.t()) :: {[Node.t()], map()}
  defp fix_nodes(nodes, uuid_map, %{respond_other: false, respond_no_response: false}),
    do: {Enum.reverse(nodes), uuid_map}

  defp fix_nodes(nodes, uuid_map, flow) do
    Enum.reduce(
      nodes,
      {[], uuid_map},
      fn node, {nodes, uuid_map} ->
        {node, uuid_map} = Node.fix_node(node, flow, uuid_map)
        {[node | nodes], uuid_map}
      end
    )
  end

  # in some cases flow editor wraps the json under a "definition" key
  @spec clean_definition(map()) :: map()
  defp clean_definition(json),
    do:
      json
      |> Map.get("definition", json)
      |> Map.delete("_ui")

  @doc """
  load the latest revision, specifically json definition from the
  flow_revision table. We return the clean definition back
  """
  @spec get_latest_definition(integer) :: map()
  def get_latest_definition(flow_id) do
    query =
      from(fr in FlowRevision,
        where: fr.revision_number == 0 and fr.flow_id == ^flow_id,
        select: fr.definition
      )

    Repo.one(query)
    # lets get rid of stuff we don't use, specifically the definition and
    # UI layout of the flow
    |> clean_definition()
  end

  @doc """
  Create a sub flow of an existing flow
  """
  @spec start_sub_flow(FlowContext.t(), Ecto.UUID.t(), non_neg_integer) ::
          {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def start_sub_flow(context, uuid, parent_id) do
    # we might want to put the current one under some sort of pause status
    flow = get_flow(context.flow.organization_id, uuid, context.status)

    parent =
      Glific.delete_multiple(
        context.results,
        ["parent", :parent, "child", :child]
      )

    FlowContext.init_context(flow, context.contact, context.status,
      parent_id: parent_id,
      delay: context.delay,
      uuids_seen: context.uuids_seen,
      # lets keep only one level of results, rather than a lot of them
      results: %{"parent" => parent}
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
      from(f in Flow,
        join: fr in assoc(f, :revisions),
        where: f.organization_id == ^organization_id,
        where: fr.flow_id == f.id,
        select: %Flow{
          id: f.id,
          name: f.name,
          uuid: f.uuid,
          is_background: f.is_background,
          is_active: f.is_active,
          keywords: f.keywords,
          ignore_keywords: f.ignore_keywords,
          respond_other: f.respond_other,
          respond_no_response: f.respond_no_response,
          organization_id: f.organization_id,
          definition: fr.definition,
          version: fr.version
        }
      )

    flow =
      query
      |> status_clause(status)
      |> args_clause(args)
      |> Repo.one!()
      |> Map.put(:status, status)

    if flow.definition["nodes"] == [] do
      flow
    else
      start_node_uuid = start_node(flow.definition["_ui"])

      flow.definition
      |> clean_definition()
      |> process(flow, start_node_uuid)
    end
  end

  @spec start_node(map()) :: Ecto.UUID.t() | nil
  defp start_node(json) do
    {node_uuid, _top, _left} =
      json["nodes"]
      |> Enum.reduce(
        {nil, 1_000_000, 1_000_000},
        fn {node_uuid, node}, {uuid, top, left} ->
          pos_top = get_in(node, ["position", "top"])
          pos_left = get_in(node, ["position", "left"])

          if pos_top < top || (pos_top == top && pos_left < left) do
            {node_uuid, pos_top, pos_left}
          else
            {uuid, top, left}
          end
        end
      )

    node_uuid
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
    if flow.definition["nodes"] == [] do
      [Flow: "Flow is empty"]
    else
      all_nodes = flow_objects(flow, :node)
      all_translation = flow.definition["localization"]

      flow.nodes
      |> Enum.reduce(
        [],
        &Node.validate(&1, &2, flow)
      )
      |> dangling_nodes(flow, all_nodes)
      |> missing_flow_context_nodes(flow, all_nodes)
      |> missing_localization(flow, all_translation)
    end
  end

  @spec flow_objects(map(), atom()) :: MapSet.t()
  defp flow_objects(flow, type) do
    flow.uuid_map
    |> Enum.filter(fn {_k, v} -> elem(v, 0) == type end)
    |> Enum.map(fn {k, _v} -> k end)
    |> MapSet.new()
  end

  @spec dangling_nodes(Keyword.t(), map(), MapSet.t()) :: Keyword.t()
  defp dangling_nodes(errors, flow, all_nodes) do
    all_exits = flow_objects(flow, :exit)

    # the first node is always reachable
    reachable_nodes =
      all_exits
      |> Enum.reduce(
        MapSet.new([flow.start_node.uuid]),
        fn e, acc ->
          {:exit, exit} = flow.uuid_map[e]
          MapSet.put(acc, exit.destination_node_uuid)
        end
      )
      |> MapSet.delete(nil)

    dangling = MapSet.difference(all_nodes, reachable_nodes)

    if MapSet.size(dangling) == 0,
      do: errors,
      else: [{dangling, "Your flow has dangling nodes", "Warning"}] ++ errors
  end

  @spec missing_flow_context_nodes(Keyword.t(), map(), MapSet.t()) :: Keyword.t()
  defp missing_flow_context_nodes(errors, flow, all_nodes) do
    flow_context_nodes =
      FlowContext
      |> where([fc], fc.flow_id == ^flow.id and is_nil(fc.completed_at))
      |> select([fc], fc.node_uuid)
      |> distinct(true)
      |> Repo.all()
      |> MapSet.new()

    if MapSet.subset?(flow_context_nodes, all_nodes),
      do: errors,
      else:
        [{FlowContext, "Some of your users in the flow have their node deleted", "Critical"}] ++
          errors
  end

  @spec missing_localization(Keyword.t(), map(), map()) :: Keyword.t()
  defp missing_localization(errors, flow, all_localization) do
    localized_nodes =
      flow.nodes
      |> Enum.reduce([], fn node, uuids ->
        node.actions
        |> Enum.reduce([], fn action, acc ->
          if action.type == "send_msg", do: acc ++ [action.uuid], else: uuids
        end)
        |> then(&(uuids ++ &1))
      end)

    has_missing_localization(errors, all_localization, localized_nodes)
  end

  @spec has_missing_localization(Keyword.t(), map(), list()) :: Keyword.t()
  defp has_missing_localization(errors, all_localization, localized_nodes) do
    all_localization
    |> Enum.reduce(errors, fn {language_local, localized_map}, errors ->
      Enum.all?(localized_nodes, fn localized_node ->
        Map.has_key?(localized_map, localized_node)
      end)
      |> then(fn localized ->
        if localized == false do
          language =
            Language
            |> where([l], l.locale == ^language_local)
            |> Repo.one()

          errors ++
            [
              {Localization,
               "Some of the send message nodes are missing translations in #{language.label}",
               "Warning"}
            ]
        else
          errors
        end
      end)
    end)
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

  @doc """
    We need to perform the execute in case template is an expression
  """
  @spec execute(Action.t(), FlowContext.t()) :: {:ok, FlowContext.t(), []}
  def execute(action, context) do
    flow = Repo.get_by(Flow, %{uuid: action.flow["uuid"]})

    contact_ids =
      Enum.reduce(action.contacts, [], &(&2 ++ [&1["uuid"]]))
      |> then(fn contact_ids ->
        if action.exclusions, do: exclude_contacts_in_flow(contact_ids), else: contact_ids
      end)

    contact_ids
    |> Enum.each(fn contact_id ->
      contact = Repo.get_by(Contact, %{id: contact_id})

      Flows.start_contact_flow(flow.id, contact, %{"parent" => context.results})
    end)

    group_ids =
      action.groups
      |> Enum.map(fn group ->
        String.to_integer(group["uuid"])
      end)

    Flows.start_group_flow(flow, group_ids, %{"parent" => context.results},
      exclusions: action.exclusions
    )

    {:ok, context, []}
  end

  @doc """
  Filter contacts which are not currently in the flow if there is exclusion
  """
  @spec exclude_contacts_in_flow(list()) :: list()
  def exclude_contacts_in_flow(contact_ids) do
    query =
      from(fc in FlowContext,
        select: fc.contact_id,
        where: fc.contact_id in ^contact_ids and is_nil(fc.completed_at)
      )

    contacts_in_flow = Repo.all(query)

    Enum.filter(contact_ids, fn contact_id ->
      {:ok, contact_id} = Glific.parse_maybe_integer(contact_id)
      contact_id not in contacts_in_flow
    end)
  end
end
