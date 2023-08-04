defmodule Glific.Flows do
  @moduledoc """
  The Flows context.
  """

  import Ecto.Query, warn: false
  import GlificWeb.Gettext

  require Logger

  alias Glific.{
    AccessControl,
    AccessControl.FlowRole,
    Caches,
    Contacts.Contact,
    Flows.ContactField,
    Groups,
    Groups.Group,
    Partners,
    Repo,
    Sheets,
    Sheets.Sheet,
    Tags.Tag,
    Templates.InteractiveTemplate,
    Templates.InteractiveTemplates,
    Templates.SessionTemplate
  }

  alias Glific.Flows.{Broadcast, Flow, FlowContext, FlowRevision}

  @doc """
  Returns the list of flows.

  ## Examples

      iex> list_flows()
      [%Flow{}, ...]

  """
  @spec list_flows(map()) :: [Flow.t()]
  def list_flows(args) do
    flows =
      Repo.list_filter_query(args, Flow, &Repo.opts_with_name/2, &filter_with/2)
      |> AccessControl.check_access(:flow)
      |> Repo.all()

    flows
    # get all the flow ids
    |> Enum.map(fn f -> f.id end)
    # get their published_draft dates
    |> get_published_draft_dates()
    # merge with the original list of flows
    |> merge_original(flows)
  end

  @spec merge_original(map(), [Flow.t()]) :: [Flow.t()]
  defp merge_original(dates, flows) do
    Enum.map(flows, fn f -> Map.merge(f, Map.get(dates, f.id, %{})) end)
  end

  @spec get_published_draft_dates([non_neg_integer]) :: map()
  defp get_published_draft_dates(flow_ids) do
    FlowRevision
    |> where([fr], fr.status == "published")
    |> or_where([fr], fr.revision_number == 0)
    |> where([fr], fr.flow_id in ^flow_ids)
    |> select([fr], %{
      id: fr.flow_id,
      status: fr.status,
      last_changed_at: fr.inserted_at
    })
    |> Repo.all()
    |> add_dates()
  end

  defp update_dates(row, value) do
    if row.status == "published",
      do: Map.put(value, :last_published_at, row.last_changed_at),
      else: Map.put(value, :last_changed_at, row.last_changed_at)
  end

  @spec add_dates(list()) :: map()
  defp add_dates(rows) do
    rows
    |> Enum.reduce(%{}, fn row, acc ->
      acc
      |> Map.put_new(row.id, %{})
      |> Map.update!(row.id, &update_dates(row, &1))
    end)
  end

  # appending lastPublishedAt and lastChangedAt field in  the flow
  @spec get_status_flow(Flow.t()) :: map()
  defp get_status_flow(flow) do
    Map.merge(
      flow,
      Map.get(
        get_published_draft_dates([flow.id]),
        flow.id,
        %{}
      )
    )
  end

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:keyword, keyword}, query ->
        from(f in query,
          where: ^keyword in f.keywords
        )

      {:uuid, uuid}, query ->
        from(q in query, where: q.uuid == ^uuid)

      {:status, status}, query ->
        query
        |> where(
          [f],
          f.id in subquery(
            FlowRevision
            |> where([fr], fr.status == ^status)
            |> select([fr], fr.flow_id)
          )
        )

      {:is_active, is_active}, query ->
        from(q in query, where: q.is_active == ^is_active)

      {:is_background, is_background}, query ->
        from(q in query, where: q.is_background == ^is_background)

      {:is_pinned, is_pinned}, query ->
        from(q in query, where: q.is_pinned == ^is_pinned)

      {:tag_ids, tag_ids}, query ->
        from(q in query, where: q.tag_id in ^tag_ids)

      {:name_or_keyword_or_tags, name_or_keyword_or_tags}, query ->
        sub_query =
          Tag
          |> where([t], ilike(t.label, ^"%#{name_or_keyword_or_tags}%"))
          |> select([t], t.id)

        query
        |> where([fr], ilike(fr.name, ^"%#{name_or_keyword_or_tags}%"))
        |> or_where(
          [fr],
          ^name_or_keyword_or_tags in fr.keywords or fr.tag_id in subquery(sub_query)
        )

      _, query ->
        query
    end)
  end

  @doc """
  Return the count of flows, using the same filter as list_flows
  """
  @spec count_flows(map()) :: integer
  def count_flows(args),
    do: Repo.count_filter(args, Flow, &Repo.filter_with/2)

  @doc """
  Gets a single flow.

  Raises `Ecto.NoResultsError` if the Flow does not exist.

  ## Examples

      iex> get_flow!(123)
      %Flow{}

      iex> get_flow!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_flow!(integer) :: Flow.t()
  def get_flow!(id) do
    with flow <- Repo.get!(Flow, id) do
      get_status_flow(flow)
    end
  end

  @doc """
  Fetches a single flow

  Returns `Resource not found` if the Interactive Template does not exist.

  ## Examples

      iex> fetch_interactive_template(123, 1)
        {:ok, %Flow{}}

      iex> fetch_interactive_template(456, 1)
        {:error, ["Elixir.Glific.Flows.Flow", "Resource not found"]}

  """
  @spec fetch_flow(integer) :: {:ok, any} | {:error, any}
  def fetch_flow(id),
    do: Repo.fetch_by(Flow, %{id: id})

  @doc """
  Creates a flow.

  ## Examples

      iex> create_flow(%{field: value})
      {:ok, %Flow{}}

      iex> create_flow(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_flow(map()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
  def create_flow(attrs) do
    user = Repo.get_current_user()

    attrs =
      Map.put(attrs, :keywords, sanitize_flow_keywords(attrs[:keywords]))
      |> Map.put_new(:uuid, Ecto.UUID.generate())

    clean_cached_flow_keywords_map(attrs.organization_id)

    with {:ok, flow} <-
           %Flow{}
           |> Flow.changeset(attrs)
           |> Repo.insert() do
      {:ok, _} =
        FlowRevision.create_flow_revision(%{
          definition: FlowRevision.default_definition(flow),
          flow_id: flow.id,
          user_id: user.id,
          organization_id: flow.organization_id
        })

      flow = get_status_flow(flow)

      if Map.has_key?(attrs, :add_role_ids),
        do: update_flow_roles(attrs, flow),
        else: {:ok, flow}
    end
  end

  @spec update_flow_roles(map(), Flow.t()) :: {:ok, Flow.t()}
  defp update_flow_roles(attrs, flow) do
    %{access_controls: access_controls} =
      attrs
      |> Map.put(:flow_id, flow.id)
      |> FlowRole.update_flow_roles()

    flow
    |> Map.put(:roles, access_controls)
    |> then(&{:ok, &1})
  end

  @doc """
  Updates a flow.

  ## Examples

      iex> update_flow(flow, %{field: new_value})
      {:ok, %Flow{}}

      iex> update_flow(flow, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_flow(Flow.t(), map()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
  def update_flow(%Flow{} = flow, attrs) do
    # first delete the cached flow
    remove_flow_cache(flow)

    attrs =
      attrs
      |> Map.merge(%{keywords: sanitize_flow_keywords(attrs[:keywords] || flow.keywords)})

    with {:ok, updated_flow} <-
           flow
           |> Flow.changeset(attrs)
           |> Repo.update() do
      if Map.has_key?(attrs, :add_role_ids),
        do: update_flow_roles(attrs, updated_flow),
        else: {:ok, updated_flow}
    end
  end

  @doc """
  Deletes a flow.

  ## Examples

      iex> delete_flow(flow)
      {:ok, %Flow{}}

      iex> delete_flow(flow)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_flow(Flow.t()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
  def delete_flow(%Flow{} = flow) do
    remove_flow_cache(flow)
    Repo.delete(flow)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking flow changes.

  ## Examples

      iex> change_flow(flow)
      %Ecto.Changeset{data: %Flow{}}

  """
  @spec change_flow(Flow.t(), map()) :: Ecto.Changeset.t()
  def change_flow(%Flow{} = flow, attrs \\ %{}) do
    Flow.changeset(flow, attrs)
  end

  defp get_user do
    user = Repo.get_current_user()

    {email, name} =
      if user,
        do: {"#{user.phone}@glific.org", user.name},
        else: {"unknown@glific.org", "Unknown Glific User"}

    %{email: email, name: name}
  end

  @doc """
  Get a list of all the revisions based on a flow UUID
  """
  @spec get_flow_revision_list(String.t()) :: %{results: list()}
  def get_flow_revision_list(flow_uuid) do
    results =
      FlowRevision
      |> join(:left, [fr], f in Flow, as: :f, on: f.id == fr.flow_id)
      |> where([fr, f], f.uuid == ^flow_uuid)
      |> select([fr, f], %FlowRevision{
        id: fr.id,
        inserted_at: fr.inserted_at,
        status: fr.status,
        revision_number: fr.revision_number,
        flow_id: fr.flow_id
      })
      |> order_by([fr], desc: fr.id)
      |> limit(15)
      |> Repo.all()

    # Instead of sorting this list we need to fetch the ordered items from the DB
    # We will optimize this more in the v0.4
    asset_list =
      results
      |> Enum.sort(fn fr1, fr2 -> fr1.id >= fr2.id end)
      |> Enum.reduce(
        [],
        fn revision, acc ->
          [
            %{
              user: get_user(),
              created_on: revision.inserted_at,
              id: revision.id,
              version: "13.0.0",
              revision: revision.id,
              status: revision.status
            }
            | acc
          ]
        end
      )

    %{results: asset_list |> Enum.reverse()}
  end

  @doc """
  Get specific flow revision by number
  """
  @spec get_flow_revision(String.t(), String.t()) :: map()
  def get_flow_revision(_flow_uuid, revision_id) do
    revision = Repo.get!(FlowRevision, revision_id)
    %{definition: revision.definition, metadata: %{issues: []}}
  end

  @doc """
  Save new revision for the flow
  """
  @spec create_flow_revision(map(), non_neg_integer()) :: FlowRevision.t()
  def create_flow_revision(definition, user_id) do
    {:ok, flow} = Repo.fetch_by(Flow, %{uuid: definition["uuid"]})

    {:ok, revision} =
      %FlowRevision{}
      |> FlowRevision.changeset(%{
        definition: definition,
        flow_id: flow.id,
        organization_id: flow.organization_id,
        user_id: user_id
      })
      |> Repo.insert()

    # Now also delete the caches for the draft status, so we can reload
    # note that we don't bother reloading the cache, since we don't expect
    # draft simulator to run often, and drafts are being saved quite often
    Caches.remove(flow.organization_id, keys_to_cache_flow(flow, "draft"))

    revision
  end

  defp check_field(json, field, acc),
    do: if(Map.has_key?(json, field), do: acc, else: [field | acc])

  @doc """
  Check the required fields for all flow objects. If missing, raise an exception
  """
  @spec check_required_fields(map(), [atom()]) :: boolean()
  def check_required_fields(json, required) do
    result =
      Enum.reduce(
        required,
        [],
        fn field, acc ->
          check_field(json, to_string(field), acc)
        end
      )

    if result == [],
      do: true,
      else:
        raise(ArgumentError,
          message:
            "Missing required fields: #{result} with node uuid: #{json["uuid"]} and type: #{json["type"]}"
        )
  end

  @doc """
  A generic json traversal and building the structure for a specific flow schema
  which is an array of objects in the json file. Used for Node/Actions, Node/Exits,
  Router/Cases, and Router/Categories
  """
  @spec build_flow_objects(list(), map(), (map(), map(), any -> {any, map()}), any) ::
          {any, map()}
  def build_flow_objects(json, uuid_map, process_fn, object \\ nil) do
    {objects, uuid_map} =
      Enum.reduce(
        json,
        {[], uuid_map},
        fn object_json, acc ->
          {object, uuid_map} = process_fn.(object_json, elem(acc, 1), object)
          {[object | elem(acc, 0)], uuid_map}
        end
      )

    {Enum.reverse(objects), uuid_map}
  end

  # Get a list of all the keys to cache the flow.
  @spec keys_to_cache_flow(Flow.t(), String.t()) :: list()
  defp keys_to_cache_flow(flow, status),
    do:
      Enum.map(flow.keywords, fn keyword -> {:flow_keyword, keyword, status} end)
      |> Enum.concat([{:flow_uuid, flow.uuid, status}, {:flow_id, flow.id, status}])

  @spec make_args(atom(), any()) :: map()
  defp make_args(key, value) do
    case key do
      :flow_uuid -> %{uuid: value}
      :flow_id -> %{id: value}
      :flow_keyword -> %{keyword: value}
      _ -> raise ArgumentError, message: "Unknown key/value pair: #{key}, #{value}"
    end
  end

  @spec load_flow_cache(tuple()) :: tuple()
  defp load_flow_cache(cache_key) do
    {organization_id, {key, value, status}} = cache_key
    Repo.put_organization_id(organization_id)
    Logger.info("Loading flow cache: #{organization_id}, #{inspect(key)}")
    args = make_args(key, value)
    flow = Flow.get_loaded_flow(organization_id, status, args)
    Caches.set(organization_id, keys_to_cache_flow(flow, status), flow)

    # We are setting the cache in the above statement with multiple keys
    # hence we are asking Cachex to just ignore this aspect. All the other
    # requests will get the cache value sent above
    {:ignore, flow}
  end

  @doc """
  A helper function to interact with the Caching API and get the cached flow.
  It will also set the loaded flow to cache in case it does not exists.
  """
  @spec get_cached_flow(non_neg_integer, {atom(), any(), String.t()}) ::
          {atom, any} | {atom(), String.t()}
  def get_cached_flow(nil, _key), do: {:ok, nil}

  def get_cached_flow(organization_id, key) do
    case Caches.fetch(organization_id, key, &load_flow_cache/1) do
      {:error, error} ->
        Logger.info("Failed to retrieve flow, #{inspect(key)}, #{error}")
        {:error, error}

      {_, flow} ->
        {:ok, flow}
    end
  end

  @doc """
  Update the cached flow from db. This typically happens when the flow definition is updated
  via the UI
  """
  @spec update_cached_flow(Flow.t(), String.t()) :: {atom, any}
  def update_cached_flow(flow, status) do
    Caches.remove(flow.organization_id, keys_to_cache_flow(flow, status))
    get_cached_flow(flow.organization_id, {:flow_uuid, flow.uuid, status})
  end

  @doc """
  Check if a flow has been activated since the time sent as a parameter
  e.g. outOfOffice will check if that flow was activated in the last 24 hours
  daily/weekly will check since start of day/week, etc
  """
  @spec flow_activated(non_neg_integer, non_neg_integer, DateTime.t()) :: boolean
  def flow_activated(flow_id, contact_id, since) do
    results =
      FlowContext
      |> where([fc], fc.flow_id == ^flow_id)
      |> where([fc], fc.contact_id == ^contact_id)
      |> where([fc], fc.inserted_at >= ^since)
      |> Repo.all()

    if results != [],
      do: true,
      else: false
  end

  @doc """
  Update latest flow revision status as published and increment the version
  Update cached flow definition
  """
  @spec publish_flow(Flow.t(), non_neg_integer()) :: {:ok, Flow.t()} | {:error, any()}
  def publish_flow(%Flow{} = flow, user_id) do
    Logger.info("Published Flow: flow_id: '#{flow.id}'")
    errors = Flow.validate_flow(flow.organization_id, "draft", %{id: flow.id})
    result = do_publish_flow(flow, user_id)

    cond do
      # if validate and published both worked
      errors == [] && elem(result, 0) == :ok ->
        {:ok, flow}

      # we had an error saving to the DB
      elem(result, 0) == :error ->
        Logger.info("Error while publishing the flow. #{inspect(result)}")
        result

      # We had an error validating the flow
      true ->
        {:errors, format_flow_errors(errors)}
    end
  end

  @spec do_publish_flow(Flow.t(), non_neg_integer()) :: {:ok, Flow.t()} | {:error, any()}
  defp do_publish_flow(%Flow{} = flow, user_id) do
    last_version = get_last_version_and_update_old_revisions(flow, user_id)
    ## if invalid flow then return the {:error, array} otherwise move forward
    {:ok, latest_revision} = Repo.fetch_by(FlowRevision, %{flow_id: flow.id, revision_number: 0})

    result =
      latest_revision
      |> FlowRevision.changeset(%{
        status: "published",
        version: last_version + 1,
        user_id: user_id
      })
      |> Repo.update()

    if elem(result, 0) == :ok do
      revision_id = get_in(elem(result, 1), [Access.key(:id, "default")])

      Logger.info(
        "Last published flow revision for flow_id: #{flow.id} is updated with revision_id: #{revision_id} by user_id: #{user_id}"
      )

      update_cached_flow(flow, "published")
    end

    result
  end

  @spec format_flow_errors(list()) :: list()
  defp format_flow_errors(errors) when is_list(errors) do
    ## we can think about the warning based on keys
    Enum.reduce(errors, [], fn error, acc ->
      [%{key: elem(error, 0), message: elem(error, 1)} | acc]
    end)
  end

  # Get version of last published flow revision
  # Archive the last published flow revision
  @spec get_last_version_and_update_old_revisions(Flow.t(), non_neg_integer()) :: integer
  defp get_last_version_and_update_old_revisions(flow, user_id) do
    FlowRevision
    |> Repo.fetch_by(%{flow_id: flow.id, status: "published"})
    |> case do
      {:ok, last_published_revision} ->
        {:ok, _} =
          last_published_revision
          |> FlowRevision.changeset(%{status: "archived", user_id: user_id})
          |> Repo.update()

        delete_old_draft_flow_revisions(flow, last_published_revision)

        last_published_revision.version

      {:error, _} ->
        0
    end
  end

  # Delete all old draft flow revisions,
  # except the ones which are created after the last archived flow revision
  @spec delete_old_draft_flow_revisions(Flow.t(), FlowRevision.t()) :: {integer(), nil | [term()]}
  defp delete_old_draft_flow_revisions(flow, old_published_revision) do
    FlowRevision
    |> where([fr], fr.flow_id == ^flow.id)
    |> where([fr], fr.id < ^old_published_revision.id)
    |> where([fr], fr.status == "draft")
    # This is temporary to keep draft revisions for 48hrs
    |> where([fr], fr.inserted_at <= fragment("CURRENT_DATE - ('2' || ?)::interval", "day"))
    |> Repo.delete_all()
  end

  @status "published"

  @doc """
  Start flow for a contact and cache the result
  """
  @spec start_contact_flow(Flow.t() | integer, Contact.t(), map()) ::
          {:ok, Flow.t()} | {:error, String.t()}

  def start_contact_flow(f, c, default_results \\ %{})

  def start_contact_flow(flow_id, %Contact{} = contact, default_results)
      when is_integer(flow_id) do
    case get_cached_flow(contact.organization_id, {:flow_id, flow_id, @status}) do
      {:ok, flow} ->
        process_contact_flow([contact], flow, default_results)

      {:error, _error} ->
        {:error, ["Flow", dgettext("errors", "Flow not found")]}
    end
  end

  def start_contact_flow(%Flow{} = flow, %Contact{} = contact, default_results),
    do: start_contact_flow(flow.id, contact, default_results)

  @spec process_contact_flow(list(), Flow.t(), map()) :: {:ok, Flow.t()}
  defp process_contact_flow(contacts, flow, default_results) do
    if flow.is_active do
      Broadcast.broadcast_contacts(flow, contacts, default_results)
      {:ok, flow}
    else
      {:error, ["Flow", dgettext("errors", "Flow is not active")]}
    end
  end

  @doc """
  Start flow for contacts of a group
  """
  @spec start_group_flow(Flow.t(), Group.t(), map(), Keyword.t()) :: {:ok, Flow.t()}
  def start_group_flow(flow, group, default_results \\ %{}, opts \\ []) do
    # the flow returned is the expanded version
    {:ok, flow} = get_cached_flow(group.organization_id, {:flow_id, flow.id, @status})
    Broadcast.broadcast_flow_to_group(flow, group, default_results, opts)
    {:ok, flow}
  end

  @doc """
  Make a copy of a flow
  """
  @spec copy_flow(Flow.t(), map()) :: {:ok, Flow.t()} | {:error, String.t()}
  def copy_flow(flow, attrs) do
    attrs =
      attrs
      |> Map.merge(%{
        version_number: flow.version_number,
        flow_type: flow.flow_type,
        organization_id: flow.organization_id,
        uuid: Ecto.UUID.generate()
      })

    with {:ok, flow_copy} <-
           %Flow{}
           |> Flow.changeset(attrs)
           |> Repo.insert() do
      Glific.State.reset()
      copy_flow_revision(flow, flow_copy)

      {:ok, flow_copy}
    end
  end

  @spec copy_flow_revision(Flow.t(), Flow.t()) :: {:ok, FlowRevision.t()} | {:error, String.t()}
  defp copy_flow_revision(flow, flow_copy) do
    user = Repo.get_current_user()

    with {:ok, latest_flow_revision} <-
           Repo.fetch_by(FlowRevision, %{flow_id: flow.id, revision_number: 0}) do
      definition_copy =
        latest_flow_revision.definition
        |> Map.merge(%{"uuid" => flow_copy.uuid})

      {:ok, _} =
        FlowRevision.create_flow_revision(%{
          definition: definition_copy,
          flow_id: flow_copy.id,
          organization_id: flow_copy.organization_id,
          user_id: user.id
        })
    end
  end

  @doc """
  Create a map of keywords that map to flow ids for each
  active organization. Also cache this value including the outOfOffice
  shortcode
  """
  @spec flow_keywords_map(non_neg_integer) :: map()
  def flow_keywords_map(organization_id) do
    case Caches.fetch(organization_id, "flow_keywords_map", &load_flow_keywords_map/1) do
      {:error, error} ->
        raise(ArgumentError,
          message: "Failed to retrieve flow_keywords_map, #{inspect(organization_id)}, #{error}"
        )

      {_, value} ->
        value
    end
  end

  @spec update_flow_keyword_map(map(), String.t(), String.t(), non_neg_integer) :: map()
  defp update_flow_keyword_map(map, status, keyword, flow_id) do
    map
    |> Map.update(
      status,
      %{keyword => flow_id},
      fn m -> Map.put(m, keyword, flow_id) end
    )
  end

  @spec add_flow_keyword_map(map(), map()) :: map()
  defp add_flow_keyword_map(flow, acc) do
    Enum.reduce(
      flow.keywords,
      acc,
      fn keyword, acc ->
        keyword = Glific.string_clean(keyword)
        acc = update_flow_keyword_map(acc, flow.status, keyword, flow.id)

        # always add to draft status if published
        if flow.status == "published",
          do: update_flow_keyword_map(acc, "draft", keyword, flow.id),
          else: acc
      end
    )
  end

  @spec load_flow_keywords_map(tuple()) :: tuple()
  defp load_flow_keywords_map(cache_key) do
    # this is of the form {organization_id, "flow_keywords_map}"
    # we want the organization_id
    organization_id = cache_key |> elem(0)
    organization = Partners.organization(organization_id)

    keyword_map =
      Flow
      |> where([f], f.organization_id == ^organization_id)
      |> where([f], f.is_active == true)
      |> join(:inner, [f], fr in FlowRevision, on: f.id == fr.flow_id)
      |> select([f, fr], %{keywords: f.keywords, id: f.id, status: fr.status})
      # the revisions table is potentially large, so we really want just a few rows from
      # it, hence this where clause
      |> where([f, fr], fr.status == "published" or fr.revision_number == 0)
      |> Repo.all(skip_organization_id: true)
      |> Enum.reduce(
        # create empty arrays always, so all map operations works
        # and wont throw an exception of "expected map, got nil"
        %{"published" => %{}, "draft" => %{}},
        fn flow, acc -> add_flow_keyword_map(flow, acc) end
      )
      |> add_default_flows(organization.out_of_office)
      |> Map.put("org_default_new_contact", organization.newcontact_flow_id)
      |> Map.put("org_default_optin", organization.optin_flow_id)

    {:commit, keyword_map}
  end

  @spec add_default_flows(map(), map()) :: map()
  defp add_default_flows(keyword_map, out_of_office),
    do:
      keyword_map
      |> do_add_default_flow(out_of_office.enabled, "outofoffice", out_of_office.flow_id)
      |> do_add_default_flow(out_of_office.enabled, "defaultflow", out_of_office.default_flow_id)

  @spec do_add_default_flow(map(), boolean(), String.t(), nil | non_neg_integer()) :: map()
  defp do_add_default_flow(keyword_map, _enabled, _flow_name, nil), do: keyword_map

  defp do_add_default_flow(keyword_map, true, flow_name, flow_id),
    do:
      keyword_map
      |> update_flow_keyword_map("published", flow_name, flow_id)
      |> update_flow_keyword_map("draft", flow_name, flow_id)

  defp do_add_default_flow(keyword_map, _, _, _), do: keyword_map

  @doc false
  @spec clean_cached_flow_keywords_map(non_neg_integer) :: list()
  defp clean_cached_flow_keywords_map(organization_id) do
    Glific.State.reset()
    Caches.remove(organization_id, ["flow_keywords_map"])
  end

  @spec sanitize_flow_keywords(list) :: list()
  defp sanitize_flow_keywords(keywords) when is_list(keywords),
    do: Enum.map(keywords, &Glific.string_clean(&1))

  defp sanitize_flow_keywords(keywords), do: keywords

  @optin_flow_keyword "optin"

  @doc """
  Check if the flow is optin flow. Currently we are
  checking based on the optin keyword only.
  """
  @spec is_optin_flow?(Flow.t()) :: boolean()
  def is_optin_flow?(nil), do: false
  def is_optin_flow?(flow), do: Enum.member?(flow.keywords, @optin_flow_keyword)

  @doc """
  import a flow from json
  """
  @spec import_flow(map(), non_neg_integer()) :: boolean()
  def import_flow(import_flow, organization_id) do
    user = Repo.get_current_user()
    interactive_template_list = import_interactive_templates(import_flow, organization_id)

    import_flow_list =
      Enum.map(import_flow["flows"], fn flow_revision ->
        with {:ok, flow} <-
               create_flow(%{
                 name: flow_revision["definition"]["name"],
                 # we are reusing existing UUIDs against the spirit of UUIDs
                 # however this allows us to support sub flows
                 uuid: flow_revision["definition"]["uuid"],
                 keywords: flow_revision["keywords"],
                 organization_id: organization_id
               }),
             {:ok, _flow_revision} <-
               FlowRevision.create_flow_revision(%{
                 definition:
                   clean_flow_definition(flow_revision["definition"], interactive_template_list),
                 flow_id: flow.id,
                 organization_id: flow.organization_id,
                 user_id: user.id
               }) do
          import_contact_field(import_flow, organization_id)
          import_groups(import_flow, organization_id)
          true
        else
          _ -> false
        end
      end)

    !Enum.member?(import_flow_list, false)
  end

  @spec clean_flow_definition(map(), list()) :: map()
  defp clean_flow_definition(definition, interactive_template_list) do
    nodes =
      definition
      |> Map.get("nodes", [])
      |> Enum.reduce([], &(&2 ++ process_node_actions(&1, interactive_template_list)))

    put_in(definition, ["nodes"], nodes)
  end

  @spec process_node_actions(map(), list()) :: list()
  defp process_node_actions(%{"actions" => actions} = node, _interactive_template_list)
       when actions == [],
       do: [node]

  defp process_node_actions(%{"actions" => actions} = node, interactive_template_list) do
    Enum.reduce(actions, [], fn action, acc ->
      template_uuid = get_in(action, ["templating", "template", "uuid"])
      sheet_url = get_in(action, ["url"])
      sheet_name = get_in(action, ["name"])

      cond do
        action["type"] == "send_msg" ->
          # checking if the imported template is present in database
          template_uuid_list = SessionTemplate |> select([st], st.uuid) |> Repo.all()

          with true <- Map.has_key?(action, "templating"),
               false <- template_uuid in template_uuid_list do
            # update the node if template uuid in the node is not present in DB
            action =
              action |> Map.delete("templating") |> put_in(["text"], "Update this with template")

            node = put_in(node, ["actions"], [action])
            acc ++ [node]
          else
            _ -> acc ++ [node]
          end

        action["type"] == "link_google_sheet" ->
          current_user = Repo.get_current_user()

          attrs = %{
            url: sheet_url,
            label: sheet_name,
            organization_id: current_user.organization_id
          }

          sheet =
            case Repo.fetch_by(Sheet, %{url: sheet_url}) do
              {:ok, sheet} ->
                sheet

              {:error, _} ->
                {:ok, sheet} = Sheets.create_sheet(attrs)
                sheet
            end

          action = Map.put(action, "sheet_id", sheet.id)
          node = put_in(node, ["actions"], [action])
          acc ++ [node]

        action["type"] == "send_interactive_msg" ->
          {:ok, action_id} = Glific.parse_maybe_integer(action["id"])

          template_id = find_interactive_template(interactive_template_list, action_id)

          node = put_in(node, ["actions"], [Map.put(action, "id", template_id)])
          acc ++ [node]

        true ->
          acc ++ [node]
      end
    end)
  end

  @spec find_interactive_template(list(), integer | nil) :: String.t()
  defp find_interactive_template(interactive_template_list, action_id) do
    {_source_id, template_id, _interactive_template_label} =
      Enum.find(interactive_template_list, fn {source_id, _template_id,
                                               _interactive_template_label} ->
        source_id == action_id
      end)

    template_id
  end

  defp import_contact_field(import_flow, organization_id) do
    import_flow["contact_field"]
    |> Enum.each(fn contact_field ->
      %{
        name: contact_field,
        organization_id: organization_id,
        shortcode: contact_field
      }
      |> ContactField.create_contact_field()
    end)
  end

  defp import_groups(import_flow, organization_id) do
    import_flow["collections"]
    |> Enum.each(fn collection ->
      Groups.get_or_create_group_by_label(collection, organization_id)
    end)
  end

  defp import_interactive_templates(import_flow, organization_id) do
    import_flow["interactive_templates"]
    |> Enum.reduce([], fn interactive_template, acc ->
      Repo.fetch_by(InteractiveTemplate, %{label: interactive_template["label"]})
      |> case do
        {:ok, db_interactive_template} ->
          acc ++
            [
              {interactive_template["source_id"], db_interactive_template.id,
               db_interactive_template.label}
            ]

        _ ->
          {:ok, new_interactive_template} =
            interactive_template
            |> Map.delete("source_id")
            |> Map.put("organization_id", organization_id)
            |> InteractiveTemplates.create_interactive_template()

          acc ++
            [
              {interactive_template["source_id"], new_interactive_template.id,
               new_interactive_template.label}
            ]
      end
    end)
  end

  @doc """
  Generate a json map with all the flows related fields.
  """
  @spec export_flow(non_neg_integer()) :: map()
  def export_flow(flow_id) do
    flow = Repo.get!(Flow, flow_id)

    export_flow_details(
      flow.uuid,
      %{"flows" => [], "contact_field" => [], "collections" => [], "interactive_templates" => []}
    )
  end

  @doc """
  Process sub flows and check if there is more sub flows in it.
  """
  @spec export_flow_details(String.t(), map()) :: map()
  def export_flow_details(flow_uuid, results) do
    if Enum.any?(results["flows"], fn flow -> Map.get(flow.definition, "uuid") == flow_uuid end) do
      results
    else
      flow = Repo.get_by(Flow, %{uuid: flow_uuid})

      # definition can be nil, hence assigning empty map if so
      # Issue #2173
      definition =
        (get_latest_definition(flow_uuid) || %{})
        |> Map.put("name", flow.name)

      results =
        Map.put(
          results,
          "flows",
          results["flows"] ++ [%{definition: definition, keywords: flow.keywords}]
        )
        |> Map.put(
          "contact_field",
          results["contact_field"] ++ export_contact_fields(definition)
        )
        |> Map.put(
          "collections",
          results["collections"] ++ export_collections(definition)
        )
        |> Map.put(
          "interactive_templates",
          results["interactive_templates"] ++ export_interactive_templates(definition)
        )

      ## here we can export more details like fields, triggers, groups and all.

      definition
      |> Map.get("nodes", [])
      |> get_sub_flows()
      |> Enum.reduce(results, &export_flow_details(&1["uuid"], &2))
    end
  end

  @spec export_collections(map()) :: list()
  defp export_collections(definition) do
    definition
    |> Map.get("nodes", [])
    |> Enum.reduce([], &(&2 ++ do_export_collections(&1)))
  end

  @spec do_export_collections(map()) :: list()
  defp do_export_collections(%{"actions" => actions}) when actions == [], do: []

  defp do_export_collections(%{"actions" => actions}) do
    action = actions |> hd

    if action["type"] == "add_contact_groups",
      do: action["groups"] |> Enum.reduce([], &(&2 ++ [&1["name"]])),
      else: []
  end

  @spec export_contact_fields(map()) :: list()
  defp export_contact_fields(definition) do
    definition
    |> Map.get("nodes", [])
    |> Enum.reduce([], &(&2 ++ do_export_contact_fields(&1)))
  end

  @spec do_export_contact_fields(map()) :: list()
  defp do_export_contact_fields(%{"actions" => actions}) when actions == [], do: []

  defp do_export_contact_fields(%{"actions" => actions}) do
    action = actions |> hd
    if action["type"] == "set_contact_field", do: [action["field"]["key"]], else: []
  end

  @spec export_interactive_templates(map()) :: list()
  defp export_interactive_templates(definition) do
    definition
    |> Map.get("nodes", [])
    |> Enum.reduce([], &(&2 ++ do_export_interactive_templates(&1)))
    |> fetch_interactive_templates_from_db()
  end

  @spec do_export_interactive_templates(map()) :: list()
  defp do_export_interactive_templates(%{"actions" => actions}) when actions == [], do: []

  defp do_export_interactive_templates(%{"actions" => actions}) do
    actions
    |> Enum.reduce([], fn action, acc ->
      if action["type"] == "send_interactive_msg", do: acc ++ [action["id"]], else: acc
    end)
  end

  defp fetch_interactive_templates_from_db(ids) do
    InteractiveTemplate
    |> where([it], it.id in ^ids)
    |> select([it], %{
      source_id: it.id,
      label: it.label,
      type: it.type,
      interactive_content: it.interactive_content,
      translations: it.translations,
      language_id: it.language_id,
      send_with_title: it.send_with_title
    })
    |> Repo.all()
  end

  @doc """
    Extract all the sub flows form the parent flow definition.
  """
  @spec get_sub_flows(list()) :: list()
  def get_sub_flows(nodes),
    do: Enum.reduce(nodes, [], &do_get_sub_flows(&1, &2))

  @spec do_get_sub_flows(map(), list()) :: list()
  defp do_get_sub_flows(%{"actions" => actions}, list),
    do:
      Enum.reduce(actions, list, fn action, acc ->
        if action["type"] == "enter_flow" and action["flow"]["name"] != "Expression",
          do: acc ++ [action["flow"]],
          else: acc
      end)

  ## Get latest flow definition to export. There is one more function with the same name in
  ## Glific.Flows.flow but that gives us the definition without UI placements.
  @spec get_latest_definition(String.t()) :: map() | nil
  defp get_latest_definition(flow_uuid) do
    FlowRevision
    |> select([fr], fr.definition)
    |> join(:inner, [fr], fl in Flow, on: fr.flow_id == fl.id)
    |> where([fr, fl], fr.revision_number == 0 and fl.uuid == ^flow_uuid)
    |> Repo.one()
  end

  @doc """
  Check if the type is a media type we handle in flows
  """
  @spec is_media_type?(atom()) :: boolean()
  def is_media_type?(type),
    do: type in [:audio, :document, :image, :video]

  @doc """
   Terminate all flows for a contact
  """
  @spec terminate_contact_flows?(non_neg_integer) :: :ok
  def terminate_contact_flows?(contact_id) do
    FlowContext.mark_flows_complete(contact_id, false, source: "terminate_contact_flows")
    :ok
  end

  @spec remove_flow_cache(Flow.t()) :: :ok
  defp remove_flow_cache(flow) do
    Caches.remove(flow.organization_id, keys_to_cache_flow(flow, "draft"))
    Caches.remove(flow.organization_id, keys_to_cache_flow(flow, "published"))
    clean_cached_flow_keywords_map(flow.organization_id)
    :ok
  end
end
