defmodule Glific.Flows.Flow do
  @moduledoc """
  The flow object which encapsulates the complete flow as emitted by
  by `https://github.com/nyaruka/floweditor`
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

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
    Settings,
    Tags.Tag,
    Templates.InteractiveTemplate
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
    :is_template,
    :respond_other,
    :respond_no_response,
    :skip_validation,
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
          is_template: boolean() | nil,
          flow_type: String.t() | nil,
          channels: [String.t()] | nil,
          status: String.t(),
          skip_validation: boolean() | nil,
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
    field(:channels, {:array, :string}, default: ["whatsapp", "web"])
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
    field(:is_template, :boolean, default: false)
    field(:respond_other, :boolean, default: false)
    field(:respond_no_response, :boolean, default: false)
    field(:skip_validation, :boolean, default: false)
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
          skip_validation: f.skip_validation,
          organization_id: f.organization_id,
          flow_type: f.flow_type,
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

  @doc """
  Helper function to get the UUID of the first node in a flow
  """
  @spec start_node(map()) :: Ecto.UUID.t() | nil
  def start_node(json) do
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
  @spec validate_flow(non_neg_integer, String.t(), map()) :: list()
  def validate_flow(organization_id, status, args) do
    organization_id
    |> get_loaded_flow(status, args)
    |> validate_flow()
  end

  @spec validate_flow(map()) :: list()
  defp validate_flow(flow) do
    if flow.definition["nodes"] == [] do
      [{Flow, "Flow is empty", "Critical"}]
    else
      all_nodes = flow_objects(flow, :node)
      all_translation = flow.definition["localization"]

      action_to_node_map =
        flow.definition["nodes"]
        |> Enum.reduce(%{}, fn node, action_to_node_map ->
          node["actions"]
          |> Enum.map(fn action -> action["uuid"] end)
          |> Enum.reduce(%{}, fn action, acc -> Map.put(acc, action, node["uuid"]) end)
          |> Map.merge(action_to_node_map)
        end)

      flow.nodes
      |> Enum.reduce(
        [],
        &Node.validate(&1, &2, flow)
      )
      |> dangling_nodes(flow, all_nodes)
      |> missing_flow_context_nodes(flow, all_nodes)
      |> missing_localization(flow, all_translation, action_to_node_map)
      |> web_channel_capability_errors(flow)
    end
  end

  # actions with no web-socket equivalent: no BSP template approval concept, and
  # broadcast payloads assume WhatsApp-specific fan-out. Interactive messages are
  # supported on the web channel (rendered by the widget), so they're not listed here.
  @unsupported_web_channel_action_types ["send_broadcast"]

  @doc false
  @spec web_channel_capability_errors(list(), map()) :: list()
  defp web_channel_capability_errors(errors, %{flow_type: :web_message} = flow) do
    flow.definition["nodes"]
    |> Enum.flat_map(fn node -> node["actions"] || [] end)
    |> Enum.reduce(errors, fn action, acc ->
      cond do
        action["type"] in @unsupported_web_channel_action_types ->
          [
            {action["uuid"],
             "Action '#{action["type"]}' is not supported on a web channel (:web_message) flow",
             "Critical"}
            | acc
          ]

        action["type"] == "send_msg" && templated_action?(action) ->
          [
            {action["uuid"],
             "A templated (HSM) 'send_msg' is not supported on a web channel (:web_message) flow",
             "Critical"}
            | acc
          ]

        true ->
          acc
      end
    end)
  end

  defp web_channel_capability_errors(errors, _flow), do: errors

  @doc """
  Derive a flow's channel type from its definition, rather than trusting an author-set value.

  `flow_type` is not editable by an author (`:flow_input` deprecates the field and the resolver
  strips it) — a flow is omnichannel (`:message`) by default and becomes web-only the moment any
  node sends a `:blocks` interactive template, which nothing but the widget can render. The
  commitment is irreversible: once a flow is `:web_message` it stays that way even if the blocks
  node is later removed, matching `web_channel_capability_errors/2` above (the inverse gate, which
  treats `:web_message` as a hard fact about the flow, not a hint). Call this at every point a
  flow definition is written — see `Glific.Flows.maybe_update_flow_type_and_channels/2`, its single caller.
  """
  @spec derive_flow_type(atom() | nil, map(), non_neg_integer()) :: atom() | nil
  def derive_flow_type(:web_message, _definition, _organization_id), do: :web_message

  def derive_flow_type(current_flow_type, definition, organization_id) do
    if web_only_node?(definition, organization_id),
      do: :web_message,
      else: current_flow_type
  end

  # Only statically-referenced templates (`action["id"]`) can be checked here; a
  # dynamically-resolved `interactive_template_expression` is not known until runtime, and such a
  # flow relies on the runtime unsupported-channel fallback (contract §8) instead. One query
  # covers every `send_interactive_msg` action in the definition, rather than one per action —
  # this runs on every floweditor autosave.
  @spec web_only_node?(map(), non_neg_integer()) :: boolean()
  defp web_only_node?(definition, organization_id) do
    template_ids =
      definition
      |> Map.get("nodes", [])
      |> List.wrap()
      |> Enum.flat_map(&(&1["actions"] || []))
      |> Enum.filter(
        &(&1["type"] == "send_interactive_msg" and (is_integer(&1["id"]) or is_binary(&1["id"])))
      )
      |> Enum.map(&Glific.parse_maybe_integer(&1["id"]))
      |> Enum.flat_map(fn
        {:ok, id} when is_integer(id) -> [id]
        _ -> []
      end)

    template_ids != [] &&
      Repo.exists?(
        from(t in InteractiveTemplate,
          where:
            t.id in ^template_ids and t.type == :blocks and t.organization_id == ^organization_id
        )
      )
  end

  @default_channels ["whatsapp", "web"]

  @doc """
  Derive a flow's `channels` set (contract §11.1) from its already-derived `flow_type`
  (`derive_flow_type/3`) and its definition, rather than trusting an author-set value. Three
  states: web-only (`["web"]`), WhatsApp-only (`["whatsapp"]`), or omnichannel
  (`["whatsapp", "web"]`, the default).

  Takes `derived_flow_type` rather than re-deriving web-only itself — `derive_flow_type/3`'s own
  web-only test (`web_only_node?/2`, a DB query per call) already carries the exact signal and
  its monotonic lock (once a flow is `:web_message` it stays that way); recomputing it here would
  run that query twice per write and risks the two derived fields disagreeing. This holds as long
  as both are always written together at the same call site — see
  `Glific.Flows.maybe_update_flow_type_and_channels/2`, this function's single caller, which
  derives `flow_type` first and passes the result straight through.

  WhatsApp-only carries no such ambiguity — the causing actions (`send_broadcast`, a templated
  HSM `send_msg`) are directly observable in the current definition, so it is recomputed in both
  directions on every call.

  A flow whose definition matches both signals in the same call (fresh web-only signal alongside
  a WhatsApp-only action) is a genuine conflict; `web_channel_capability_errors/2` above already
  rejects publishing such a flow, so this function does not need a second error path — it simply
  favors web, matching `derive_flow_type/3`'s own priority.
  """
  @spec derive_channels(atom() | nil, map()) :: list(String.t())
  def derive_channels(derived_flow_type, definition) do
    cond do
      derived_flow_type == :web_message -> ["web"]
      whatsapp_only_node?(definition) -> ["whatsapp"]
      true -> @default_channels
    end
  end

  # Exactly the set `web_channel_capability_errors/2` uses to reject these actions on a
  # `:web_message` flow — reused here (rather than gated by current flow_type) so the signal is
  # observable regardless of the flow's current channels.
  @spec whatsapp_only_node?(map()) :: boolean()
  defp whatsapp_only_node?(definition) do
    definition
    |> Map.get("nodes", [])
    |> List.wrap()
    |> Enum.flat_map(&(&1["actions"] || []))
    |> Enum.any?(fn action ->
      action["type"] in @unsupported_web_channel_action_types ||
        (action["type"] == "send_msg" && templated_action?(action))
    end)
  end

  @spec templated_action?(map()) :: boolean()
  defp templated_action?(action),
    do: is_map(action["templating"]) && map_size(action["templating"]) > 0

  @spec flow_objects(map(), atom()) :: MapSet.t()
  defp flow_objects(flow, type) do
    flow.uuid_map
    |> Enum.filter(fn {_k, v} -> elem(v, 0) == type end)
    |> Enum.map(fn {k, _v} -> k end)
    |> MapSet.new()
  end

  @spec dangling_nodes(list(), map(), MapSet.t()) :: list()
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
      else: [{dangling, "Your flow has dangling nodes", "Warning"} | errors]
  end

  @spec missing_flow_context_nodes(list(), map(), MapSet.t()) :: list()
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
      else: [
        {FlowContext, "Some of your users in the flow have their node deleted", "Critical"}
        | errors
      ]
  end

  @spec missing_localization(list(), map(), map(), map()) :: list()
  defp missing_localization(errors, flow, all_localization, action_to_node_map) do
    localizable_nodes_list =
      flow.nodes
      |> Enum.reduce([], fn node, uuids ->
        node.actions
        |> Enum.reduce(uuids, fn action, acc ->
          cond do
            action.type == "send_msg" && is_nil(action.templating) ->
              [{"message", action.uuid} | acc]

            # Skipping send_msg node where expression is being used
            action.type == "send_msg" && !is_nil(action.templating) &&
                !is_nil(action.templating.expression) ->
              acc

            action.type == "send_msg" && !is_nil(action.templating) ->
              language_id = Integer.to_string(action.templating.template.language_id)

              available_translation_ids =
                Map.keys(action.templating.template.translations) ++ [language_id]

              [{"template", {action.uuid, available_translation_ids}} | acc]

            true ->
              acc
          end
        end)
      end)

    errors
    |> has_missing_localization(
      localizable_nodes_list,
      all_localization,
      flow.organization_id,
      action_to_node_map
    )
    |> has_missing_translated_template(
      localizable_nodes_list,
      all_localization,
      action_to_node_map
    )
  end

  @spec has_missing_localization(list(), list(), map(), non_neg_integer(), map()) ::
          list()
  defp has_missing_localization(
         errors,
         localizable_nodes_list,
         all_localization,
         organization_id,
         action_to_node_map
       ) do
    localizable_nodes =
      Enum.reduce(localizable_nodes_list, [], fn {type, node_uuid}, acc ->
        if type == "message", do: [node_uuid | acc], else: acc
      end)

    localization_map =
      all_localization
      |> make_localization_map(localizable_nodes)

    all_languages =
      localization_map
      |> Map.values()
      |> Enum.flat_map(fn language_label -> language_label end)
      |> Enum.uniq()

    # get language labels here in one query for all languages if you want
    num_languages = length(all_languages)
    language_labels = Settings.locale_label_map(organization_id)

    localizable_nodes
    |> Enum.reduce(
      errors,
      fn action_uuid, errors ->
        node_languages = Map.get(localization_map, action_uuid, [])

        if length(node_languages) != num_languages do
          node_uuid =
            action_to_node_map
            |> Map.get(action_uuid)
            |> String.slice(-4, 4)

          (all_languages -- node_languages)
          |> Enum.reduce(errors, fn locale, acc ->
            [
              {Localization,
               "Node #{node_uuid} is missing translations in #{language_labels[locale]}",
               "Warning"}
              | acc
            ]
          end)
        else
          errors
        end
      end
    )
  end

  # lets transform the localization to a map
  # whose key is the node uuid, and values are the languages it has
  @spec make_localization_map(map(), list()) :: map()
  defp make_localization_map(all_localization, localizable_nodes) do
    all_localization
    # For all languages
    |> Enum.reduce(
      %{},
      fn {language_local, localization}, localization_map ->
        localization
        # For all nodes that have a translation
        |> Enum.reduce(
          localization_map,
          fn {uuid, value}, acc ->
            if Map.get(value, "text", false) do
              # add the language to the localization_map for that node
              Map.update(
                acc,
                uuid,
                [language_local],
                fn existing_language_local -> [language_local | existing_language_local] end
              )
            else
              # skipping nodes where localisation was saved but text was deleted
              acc
            end
          end
        )
      end
    )
    |> remove_deleted_node_localization(localizable_nodes)
  end

  @spec remove_deleted_node_localization(map(), list()) :: map()
  defp remove_deleted_node_localization(localization_map, localizable_nodes) do
    localization_map
    |> Enum.reduce(%{}, fn {node, localization_label}, acc ->
      if node in localizable_nodes do
        Map.put(acc, node, localization_label)
      else
        acc
      end
    end)
  end

  @spec has_missing_translated_template(list(), list(), map(), map()) :: list()
  defp has_missing_translated_template(
         errors,
         localizable_nodes_list,
         all_localization,
         action_to_node_map
       ) do
    localizable_template_nodes =
      Enum.reduce(localizable_nodes_list, [], fn {type, uuid_tuple}, acc ->
        if type == "template", do: [uuid_tuple | acc], else: acc
      end)

    # checking in message nodes as templates can have multiple translation but for a specific flow only one is needed
    localizable_message_nodes =
      Enum.reduce(localizable_nodes_list, [], fn {type, node_uuid}, acc ->
        if type == "message", do: [node_uuid | acc], else: acc
      end)

    locale_list =
      all_localization
      |> make_localization_map(localizable_message_nodes)
      |> Map.values()
      |> Enum.flat_map(fn language_label -> language_label end)
      |> Enum.uniq()

    language_map =
      Settings.get_language_map()
      |> Enum.reduce(%{}, fn {language_key, language_value}, acc ->
        if language_value.locale in locale_list,
          do: Map.put(acc, language_key, language_value),
          else: acc
      end)

    language_map_ids = Map.keys(language_map)

    Enum.reduce(localizable_template_nodes, [], fn {action_uuid, translation_ids}, acc ->
      translation_ids = translation_ids |> Enum.map(&String.to_integer/1)
      missing_ids = language_map_ids -- translation_ids

      if Enum.empty?(missing_ids) do
        acc
      else
        [
          Enum.map(missing_ids, fn language_id ->
            language = Map.get(language_map, language_id)

            node_uuid =
              action_to_node_map
              |> Map.get(action_uuid)
              |> String.slice(-4, 4)

            "Node #{node_uuid} with template is missing translations in #{language.label}"
          end)
          | acc
        ]
      end
    end)
    |> Enum.flat_map(fn node_error -> node_error end)
    |> Enum.reduce(errors, fn language_error, acc ->
      [{Localization, language_error, "Warning"} | acc]
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
