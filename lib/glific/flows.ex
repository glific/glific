defmodule Glific.Flows do
  @moduledoc """
  The Flows context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Caches,
    Flows.Flow,
    Flows.FlowContext,
    Flows.FlowRevision,
    Repo
  }

  @doc """
  Returns the list of flows.

  ## Examples

      iex> list_flows()
      [%Flow{}, ...]

  """
  @spec list_flows(map()) :: [Flow.t()]
  def list_flows(args \\ %{}),
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
  def count_flows(args \\ %{}),
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

    update_cached_flow(flow.uuid)
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
  @spec get_cached_flow(any, any) :: {atom, any}
  def get_cached_flow(key, args) do
    with {:ok, false} <- Caches.get(key) do
      flow = Flow.get_loaded_flow(args)
      Caches.set([flow.uuid | flow.keywords], flow)
    end
  end

  @doc """
  Update the cached flow from db. This typically happens when the flow definition is updated
  via the UI
  """
  @spec update_cached_flow(Flow.t()) :: {atom, any}
  def update_cached_flow(flow_uuid) do
    flow = Flow.get_loaded_flow(%{uuid: flow_uuid})
    Caches.remove([flow.uuid, flow.shortcode])
    Caches.set([flow.uuid, flow.shortcode], flow)
  end

  @doc """
  Check if a flow has been activated for a specific contact id in the
  past N minutes
  """
  @spec flow_activated(non_neg_integer, non_neg_integer, integer) :: boolean
  def flow_activated(flow_id, contact_id, go_back \\ 24 * 60) do
    # we are asking for time in minutes, we need to convert to seconds
    since = DateTime.add(DateTime.utc_now(), -1 * go_back * 60)

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
end
