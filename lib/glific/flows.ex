defmodule Glific.Flows do
  @moduledoc """
  The Flows context.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
    Caches,
    Contacts,
    Contacts.Contact,
    Flows.Flow,
    Flows.FlowContext,
    Flows.FlowRevision,
    Groups.Group,
    Partners,
    Repo
  }

  @doc """
  Returns the list of flows.

  ## Examples

      iex> list_flows()
      [%Flow{}, ...]

  """
  @spec list_flows(map()) :: [Flow.t()]
  def list_flows(%{filter: %{organization_id: _organization_id}} = args),
    do: Repo.list_filter(args, Flow, &Repo.opts_with_name/2, &filter_with/2)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:keyword, keyword}, query ->
        from f in query,
          where: ^keyword in f.keywords

      {:uuid, uuid}, query ->
        from q in query, where: q.uuid == ^uuid

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

      _, query ->
        query
    end)
  end

  @doc """
  Return the count of tags, using the same filter as list_tags
  """
  @spec count_flows(map()) :: integer
  def count_flows(%{filter: %{organization_id: _organization_id}} = args),
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
  def get_flow!(id), do: Repo.get!(Flow, id)

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
    attrs =
      Map.merge(
        attrs,
        %{
          uuid: Ecto.UUID.generate(),
          keywords: sanitize_flow_keywords(attrs[:keywords])
        }
      )

    clean_cached_flow_keywords_map(attrs.organization_id)

    with {:ok, flow} <-
           %Flow{}
           |> Flow.changeset(attrs)
           |> Repo.insert() do
      {:ok, _} =
        FlowRevision.create_flow_revision(%{
          definition: FlowRevision.default_definition(flow),
          flow_id: flow.id,
          organization_id: flow.organization_id
        })

      {:ok, flow}
    end
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
    Caches.remove(flow.organization_id, [flow.uuid | flow.keywords])
    clean_cached_flow_keywords_map(flow.organization_id)

    attrs =
      attrs
      |> Map.merge(%{keywords: sanitize_flow_keywords(attrs[:keywords])})

    flow
    |> Flow.changeset(attrs)
    |> Repo.update()
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

    # We should fix this to get the logged in user
    user = %{email: "user@glific.com", name: "Glific User"}

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
              user: user,
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
  @spec create_flow_revision(map()) :: FlowRevision.t()
  def create_flow_revision(definition) do
    {:ok, flow} = Repo.fetch_by(Flow, %{uuid: definition["uuid"]})

    {:ok, revision} =
      %FlowRevision{}
      |> FlowRevision.changeset(%{
        definition: definition,
        flow_id: flow.id,
        organization_id: flow.organization_id
      })
      |> Repo.insert()

    # Now also delete the caches for the draft status, so we can reload
    # note that we dont bother reloading the cache, since we dont expect
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
      else: raise(ArgumentError, message: "Missing required fields: #{result}")
  end

  @doc """
  A generic json traversal and building the structure for a specific flow schema
  which is an array of objects in the json file. Used for Node/Actions, Node/Exits,
  Router/Cases, and Router/Categories
  """
  @spec build_flow_objects(map(), map(), (map(), map(), any -> {any, map()}), any) ::
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

  @spec load_cache(tuple()) :: tuple()
  defp load_cache(cache_key) do
    {organization_id, {key, value, status}} = cache_key
    Repo.put_organization_id(organization_id)
    Logger.info("Loading flow cache: #{organization_id}, #{inspect(key)}")
    args = make_args(key, value)
    flow = Flow.get_loaded_flow(organization_id, status, args)
    Caches.set(organization_id, keys_to_cache_flow(flow, status), flow)
    {:ignore, flow}
  end

  @doc """
  A helper function to interact with the Caching API and get the cached flow.
  It will also set the loaded flow to cache in case it does not exists.
  """
  @spec get_cached_flow(non_neg_integer, {atom(), any(), String.t()}) :: {atom, any} | atom()
  def get_cached_flow(nil, _key), do: {:ok, nil}

  def get_cached_flow(organization_id, key) do
    case Caches.fetch(organization_id, key, &load_cache/1) do
      {:error, error} ->
        raise(ArgumentError,
          message: "Failed to retrieve flow, #{inspect(key)}, #{error}"
        )

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
  e.g. outofoffice will check if that flow was activated in the last 24 hours
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
  @spec publish_flow(Flow.t()) :: {:ok, Flow.t()}
  def publish_flow(%Flow{} = flow) do
    Logger.info("Published Flow: flow_id: '#{flow.id}'")

    last_version = get_last_version_and_update_old_revisions(flow)

    with {:ok, latest_revision} <-
           FlowRevision
           |> Repo.fetch_by(%{flow_id: flow.id, revision_number: 0}) do
      {:ok, _} =
        latest_revision
        |> FlowRevision.changeset(%{status: "published", version: last_version + 1})
        |> Repo.update()

      # we need to fix this depending on where we are making the flow a beta or the published version
      update_cached_flow(flow, "published")
    end

    {:ok, flow}
  end

  # Get version of last published flow revision
  # Archive the last published flow revision
  @spec get_last_version_and_update_old_revisions(Flow.t()) :: integer
  defp get_last_version_and_update_old_revisions(flow) do
    FlowRevision
    |> Repo.fetch_by(%{flow_id: flow.id, status: "published"})
    |> case do
      {:ok, last_published_revision} ->
        {:ok, _} =
          last_published_revision
          |> FlowRevision.changeset(%{status: "archived"})
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
    |> Repo.delete_all()
  end

  @doc """
  Start flow for a contact
  """
  @spec start_contact_flow(Flow.t(), Contact.t()) :: {:ok, Flow.t()} | {:error, String.t()}
  def start_contact_flow(%Flow{} = flow, %Contact{} = contact) do
    status = "published"

    {:ok, flow} = get_cached_flow(contact.organization_id, {:flow_id, flow.id, status})

    if Contacts.can_send_message_to?(contact),
      do: process_contact_flow([contact], flow, status),
      else: {:error, ["contact", "Cannot send the message to the contact."]}
  end

  @doc """
  Start flow for contacts of a group
  """
  @spec start_group_flow(Flow.t(), Group.t()) :: {:ok, Flow.t()}
  def start_group_flow(%Flow{} = flow, %Group{} = group) do
    status = "published"

    {:ok, flow} = get_cached_flow(group.organization_id, {:flow_id, flow.id, status})

    group = group |> Repo.preload([:contacts])
    process_contact_flow(group.contacts, flow, status)
  end

  @doc """
  Make a copy of a flow
  """
  @spec copy_flow(Flow.t(), map()) :: {:ok, Flow.t()} | {:error, String.t()}
  def copy_flow(%Flow{} = flow, attrs) do
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
      copy_flow_revision(flow, flow_copy)

      {:ok, flow_copy}
    end
  end

  @spec copy_flow_revision(Flow.t(), Flow.t()) :: {:ok, FlowRevision.t()} | {:error, String.t()}
  defp copy_flow_revision(flow, flow_copy) do
    with {:ok, latest_flow_revision} <-
           Repo.fetch_by(FlowRevision, %{flow_id: flow.id, revision_number: 0}) do
      definition_copy =
        latest_flow_revision.definition
        |> Map.merge(%{"uuid" => flow_copy.uuid})

      {:ok, _} =
        FlowRevision.create_flow_revision(%{
          definition: definition_copy,
          flow_id: flow_copy.id,
          organization_id: flow_copy.organization_id
        })
    end
  end

  @spec process_contact_flow(list(), Flow.t(), String.t()) :: {:ok, Flow.t()}
  defp process_contact_flow(contacts, flow, status) do
    organization = Partners.organization(flow.organization_id)
    # lets do 90% of organization bsp limit to allow replies to come in and be processed
    limit = div(organization.services["bsp"].keys["bsp_limit"] * 90, 100)

    _ignore =
      Enum.reduce(
        contacts,
        0,
        fn contact, count ->
          if Contacts.can_send_message_to?(contact) do
            FlowContext.init_context(flow, contact, status)

            if count + 1 == limit do
              Process.sleep(1000)
              0
            else
              count + 1
            end
          else
            count
          end
        end
      )

    {:ok, flow}
  end

  @doc """
  Create a map of keywords that map to flow ids for each
  active organization. Also cache this value including the outoffice
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

  @spec load_flow_keywords_map(tuple()) :: tuple()
  defp load_flow_keywords_map(cache_key) do
    # this is of the form {organization_id, "flow_keywords_map}"
    # we want the organization_id
    organization_id = cache_key |> elem(0)

    value =
      Flow
      |> where([f], f.organization_id == ^organization_id)
      |> select([:keywords, :id])
      |> Repo.all(skip_organization_id: true)
      |> Enum.reduce(
        %{},
        fn flow, acc ->
          Enum.reduce(flow.keywords, acc, fn keyword, acc ->
            ## Keyword matching for the flow is case insenstive.
            ## So let's clean the keywords before generating the map.
            keyword = Glific.string_clean(keyword)
            Map.put(acc, keyword, flow.id)
          end)
        end
      )

    organization = Partners.organization(organization_id)

    organization =
      if organization.out_of_office.enabled and organization.out_of_office.flow_id,
        do: Map.put(value, "outofoffice", organization.out_of_office.flow_id),
        else: value

    {:commit, organization}
  end

  @doc false
  @spec clean_cached_flow_keywords_map(non_neg_integer) :: list()
  defp clean_cached_flow_keywords_map(organization_id),
    do: Caches.remove(organization_id, ["flow_keywords_map"])

  @spec sanitize_flow_keywords(list) :: list()
  defp sanitize_flow_keywords(keywords) when is_list(keywords),
    do: Enum.map(keywords, &Glific.string_clean(&1))

  defp sanitize_flow_keywords(keywords), do: keywords
end
