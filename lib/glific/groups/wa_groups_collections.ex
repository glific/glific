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
          wa_groups_collections: [WAGroupsCollection.t()],
          collection_wa_groups: [WAGroupsCollection.t()],
          wa_groups_deleted: non_neg_integer
        }

  embedded_schema do
    field(:wa_groups_deleted, :integer, default: 0)
    embeds_many(:wa_groups_collections, WAGroupsCollection)
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
    WAGroupsCollection
    |> Repo.all()
    |> IO.inspect()

    args
    |> Repo.list_filter_query(WAGroupsCollection, &Repo.opts_with_id/2, &filter_with/2)
    |> Repo.all()
    |> IO.inspect()
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
  @spec update_wa_groups_collection(%{
          :add_wa_group_ids => any(),
          :delete_wa_group_ids => [integer()],
          :group_id => integer(),
          optional(any()) => any()
        }) :: Glific.Groups.WaGroupsCollection.t()

  def update_wa_groups_collection(
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

    {wa_groups_deleted, _} = delete_group_wa_group_by_ids(group_id, delete_ids)

    %WaGroupsCollections{
      wa_groups_deleted: wa_groups_deleted,
      collection_wa_groups: collection_wa_groups
    }
  end

  @doc false
  @spec delete_group_wa_group_by_ids(integer, list()) :: {integer(), nil | [term()]}
  def delete_group_wa_group_by_ids(group_id, delete_ids) do
    fields = {{:group_id, group_id}, {:wa_group_id, delete_ids}}
    Repo.delete_relationships_by_ids(WAGroupsCollection, fields)
  end
end
