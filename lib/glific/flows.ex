defmodule Glific.Flows do
  @moduledoc """
  The Flows context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Caches,
    Contacts,
    Contacts.Contact,
    Flows.Flow,
    Flows.FlowContext,
    Flows.FlowRevision,
    Groups.Group,
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
  def create_flow(attrs \\ %{}) do
    attrs = Map.merge(attrs, %{uuid: Ecto.UUID.generate()})

    with {:ok, flow} <-
           %Flow{}
           |> Flow.changeset(attrs)
           |> Repo.insert() do
      {:ok, _} =
        FlowRevision.create_flow_revision(%{
          definition: FlowRevision.default_definition(flow),
          flow_id: flow.id
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
    flow = get_flow_with_revision(flow_uuid)
    # We should fix this to get the logged in user
    user = %{email: "user@glific.com", name: "Glific User"}

    asset_list =
      Enum.reduce(
        flow.revisions,
        [],
        fn revision, acc ->
          [
            %{
              user: user,
              created_on: revision.inserted_at,
              id: revision.id,
              version: "13.0.0",
              revision: revision.id
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

  # Preload revisions in a flow.
  # We still need to do some refactoring on this approch
  @spec get_flow_with_revision(String.t()) :: Flow.t()
  defp get_flow_with_revision(flow_uuid) do
    {:ok, flow} = Repo.fetch_by(Flow, %{uuid: flow_uuid})
    Repo.preload(flow, :revisions)
  end

  @doc """
  Save new revision for the flow
  """
  @spec create_flow_revision(map()) :: FlowRevision.t()
  def create_flow_revision(definition) do
    {:ok, flow} = Repo.fetch_by(Flow, %{uuid: definition["uuid"]})

    {:ok, revision} =
      %FlowRevision{}
      |> FlowRevision.changeset(%{definition: definition, flow_id: flow.id})
      |> Repo.insert()

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

  @doc """
  A helper function to interact with the Caching API and get the cached flow.
  It will also set the loaded flow to cache in case it does not exists.
  """
  @spec get_cached_flow(non_neg_integer, any, any) :: {atom, any}
  def get_cached_flow(organization_id, key, args) do
    with {:ok, false} <- Caches.get(organization_id, key) do
      flow = Flow.get_loaded_flow(args |> Map.merge(%{organization_id: organization_id}))
      Caches.set(organization_id, [flow.uuid | flow.keywords], flow)
    end
  end

  @doc """
  Update the cached flow from db. This typically happens when the flow definition is updated
  via the UI
  """
  @spec update_cached_flow(Flow.t()) :: {atom, any}
  def update_cached_flow(flow) do
    flow = Flow.get_loaded_flow(%{uuid: flow.uuid})
    Caches.remove(flow.organization_id, [flow.uuid | flow.keywords])
    Caches.set(flow.organization_id, [flow.uuid | flow.keywords], flow)
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
  Update latest flow revision status as done
  Reset old published flow revision status as draft
  Update cached flow definition
  """
  @spec publish_flow(Flow.t()) :: {:ok, Flow.t()}
  def publish_flow(%Flow{} = flow) do
    with {:ok, old_published_revision} <-
           Repo.fetch_by(FlowRevision, %{flow_id: flow.id, status: "done"}) do
      {:ok, _} =
        old_published_revision
        |> FlowRevision.changeset(%{status: "draft"})
        |> Repo.update()
    end

    with {:ok, latest_revision} <-
           FlowRevision
           |> Repo.fetch_by(%{flow_id: flow.id, revision_number: 0}) do
      {:ok, _} =
        latest_revision
        |> FlowRevision.changeset(%{status: "done"})
        |> Repo.update()

      update_cached_flow(flow)
    end

    {:ok, flow}
  end

  @doc """
  Start flow for a contact
  """
  @spec start_contact_flow(Flow.t(), Contact.t()) :: {:ok, Flow.t()} | {:error, String.t()}
  def start_contact_flow(%Flow{} = flow, %Contact{} = contact) do
    {:ok, flow} = get_cached_flow(contact.organization_id, flow.id, %{id: flow.id})

    if Contacts.can_send_message_to?(contact),
      do: process_contact_flow([contact], flow),
      else: {:error, ["contact", "Cannot send the message to the contact."]}
  end

  @doc """
  Start flow for contacts of a group
  """
  @spec start_group_flow(Flow.t(), Group.t()) :: {:ok, Flow.t()}
  def start_group_flow(%Flow{} = flow, %Group{} = group) do
    {:ok, flow} = get_cached_flow(group.organization_id, flow.id, %{id: flow.id})
    group = group |> Repo.preload([:contacts])
    process_contact_flow(group.contacts, flow)
  end

  @spec process_contact_flow(list(), Flow.t()) :: {:ok, Flow.t()}
  defp process_contact_flow(contacts, flow) do
    _list =
      Enum.map(contacts, fn contact ->
        if Contacts.can_send_message_to?(contact), do: FlowContext.init_context(flow, contact)
      end)

    {:ok, flow}
  end

  @doc """
  Create a map of keywords that map to flow ids for each
  active organization
  """
  @spec flow_keywords_map(non_neg_integer | nil) :: map()
  def flow_keywords_map(organization_id \\ nil) do
    flow_keywords_map =
      Flow
      |> select([:keywords, :id])
      |> Repo.all()
      |> Enum.reduce(%{}, fn flow, acc ->
        Enum.reduce(flow.keywords, acc, fn keyword, acc ->
          Map.put(acc, keyword, flow.id)
        end)
      end)

    # we need to fix this and retrieve for all active organization ids
    if is_nil(organization_id),
      do: flow_keywords_map,
      else: %{organization_id: flow_keywords_map}
  end
end
