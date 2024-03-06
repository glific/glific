defmodule Glific.Groups.WaGroupsCollections do
  @moduledoc """
  Simple container to hold all the contact groups we associate with one contact
  """

  alias Glific.{
    Groups.WAGroupsCollection,
    # Groups.WaGroupsCollections,
    Repo
  }

  use Ecto.Schema
  import Ecto.Query, warn: false

  @primary_key false

  @type t() :: %__MODULE__{
          wa_groups_collections: [WAGroupsCollection.t()],
          # group_wa_groups: [WAGroupsCollection.t()],
          # wa_groups_deleted: non_neg_integer
        }

  embedded_schema do
    # field(:wa_group_delete, :integer, default: 0)
    embeds_many(:wa_groups_collections, WAGroupsCollection)
    # embeds_many(:group_wa_groups, WAGroupsCollection)
  end

  @doc """
  Returns the list of contact whatsapp groups structs.

  ## Examples

      iex> list_wa_groups_colection()
      [%WAGroupsCollection{}, ...]

  """
  @spec list_wa_groups_colection(map()) :: [WAGroupsCollection.t()]
  def list_wa_groups_colection(args) do
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
  @spec create_wa_groups_collection(map()) :: {:ok, WAGroupsCollection.t()} | {:error, Ecto.Changeset.t()}
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
end
