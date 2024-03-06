defmodule Glific.Groups.WaGroupsCollections do
  @moduledoc """
  Simple container to hold all the collection we associate with one whastapp group
  """

  alias Glific.{
    Groups.WAGroupsCollection,
    Groups.WaGroupsCollections,
    Repo
  }

  use Ecto.Schema
  import Ecto.Query, warn: false

  @primary_key false

  @type t() :: %__MODULE__{
          collection_wa_groups: [WAGroupsCollection.t()],
          wa_groups_deleted: non_neg_integer
        }

  embedded_schema do
    field(:wa_groups_deleted, :integer, default: 0)
    embeds_many(:collection_wa_groups, WAGroupsCollection)
  end

  @doc """
  Returns the list of whatsapp groups collections structs.

  ## Examples

      iex> list_wa_groups_collection()
      [%WAGroupsCollection{}, ...]

  """
  @spec list_wa_groups_collection(map()) :: [WAGroupsCollection.t()]
  def list_wa_groups_collection(args) do
    args
    |> Repo.list_filter_query(WAGroupsCollection, &Repo.opts_with_id/2, &filter_with/2)
    |> Repo.all()
  end

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:group_id, group_id}, query ->
        where(query, [q], q.group_id == ^group_id)

      _, query ->
        query
    end)
  end

  @doc false
  @spec create_wa_groups_collection(map()) ::
          {:ok, WAGroupsCollection.t()} | {:error, Ecto.Changeset.t()}
  def create_wa_groups_collection(attrs \\ %{}) do
    # check if an entry exists
    attrs = Map.take(attrs, [:group_id, :wa_group_id, :organization_id])

    case Repo.fetch_by(WAGroupsCollection, attrs) do
      {:ok, cg} ->
        {:ok, cg}

      {:error, _} ->
        %WAGroupsCollection{}
        |> WAGroupsCollection.changeset(attrs)
        |> Repo.insert()
    end
  end

  @doc false
  @spec update_collection_wa_group(%{
          :group_id => integer(),
          :add_wa_group_ids => any(),
          :delete_wa_group_ids => [integer()],
          optional(any()) => any()
        }) :: Glific.Groups.WaGroupsCollection.t()

  def update_collection_wa_group(
        %{
          group_id: group_id,
          add_wa_group_ids: add_ids,
          delete_wa_group_ids: delete_ids
        } = attrs
      ) do
    collection_wa_groups =
      Enum.reduce(
        add_ids,
        [],
        fn wa_group_id, acc ->
          case create_wa_groups_collection(Map.put(attrs, :wa_group_id, wa_group_id)) do
            {:ok, wa_groups_collection} -> [wa_groups_collection | acc]
            _ -> acc
          end
        end
      )

    {wa_groups_deleted, _} = delete_collection_by_ids(group_id, delete_ids)

    %WaGroupsCollections{
      wa_groups_deleted: wa_groups_deleted,
      collection_wa_groups: collection_wa_groups
    }
  end

  @doc false
  @spec update_wa_group_collection(%{
          :wa_group_id => integer(),
          :add_group_ids => any(),
          :delete_group_ids => [integer()],
          optional(any()) => any()
        }) :: Glific.Groups.WaGroupsCollection.t()

  def update_wa_group_collection(
        %{
          wa_group_id: wa_group_id,
          add_group_ids: add_ids,
          delete_group_ids: delete_ids
        } = attrs
      ) do
    wa_group_collection =
      Enum.reduce(
        add_ids,
        [],
        fn group_id, acc ->
          case create_wa_groups_collection(Map.put(attrs, :group_id, group_id)) do
            {:ok, wa_groups_collection} -> [wa_groups_collection | acc]
            _ -> acc
          end
        end
      )

    {wa_groups_deleted, _} = delete_wa_groups_by_ids(wa_group_id, delete_ids)

    %WaGroupsCollections{
      wa_groups_deleted: wa_groups_deleted,
      collection_wa_groups: wa_group_collection
    }
  end

  @doc """
  Delete wa groups
  """
  @spec delete_wa_groups_by_ids(integer, list()) :: {integer(), nil | [term()]}
  def delete_wa_groups_by_ids(wa_group_id, group_ids) do
    fields = {{:wa_group_id, wa_group_id}, {:group_id, group_ids}}
    Repo.delete_relationships_by_ids(WAGroupsCollection, fields)
  end

  @doc false
  @spec delete_collection_by_ids(integer, list()) :: {integer(), nil | [term()]}
  def delete_collection_by_ids(group_id, wa_group_id) do
    fields = {{:group_id, group_id}, {:wa_group_id, wa_group_id}}
    Repo.delete_relationships_by_ids(WAGroupsCollection, fields)
  end
end
