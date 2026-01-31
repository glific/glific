defmodule Glific.Filesearch.VectorStore do
  @moduledoc """
  VectorStore schema that maps openAI VectorStores
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Glific.Filesearch.Assistant
  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo
  }

  @required_fields [
    :organization_id,
    :vector_store_id,
    :name
  ]
  @optional_fields [
    :files,
    :size,
    :status
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          vector_store_id: String.t() | nil,
          name: String.t() | nil,
          files: map() | nil,
          size: integer() | nil,
          status: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          assistants: [Assistant.t()] | Ecto.Association.NotLoaded.t() | nil
        }

  schema "openai_vector_stores" do
    field :vector_store_id, :string
    field :name, :string
    field :files, :map
    field :size, :integer
    field :status, :string
    belongs_to :organization, Organization
    has_many :assistants, Assistant
    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(VectorStore.t(), map()) :: Ecto.Changeset.t()
  def changeset(vector_store, attrs) do
    vector_store
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:vector_store_id, :organization_id])
    |> unique_constraint([:name, :organization_id],
      name: :openai_assistants_name_organization_id_index
    )
  end

  @doc """
  Creates VectorStore
  """
  @spec create_vector_store(map()) :: {:ok, VectorStore.t()} | {:error, Ecto.Changeset.t()}
  def create_vector_store(attrs) do
    %VectorStore{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Upserts VectorStore
  """
  @spec upsert_vector_store(map()) :: {:ok, VectorStore.t()} | {:error, Ecto.Changeset.t()}
  def upsert_vector_store(attrs) do
    conflict_opts = attrs |> Map.take([:name, :files, :size, :status]) |> Map.to_list()

    %VectorStore{}
    |> changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: conflict_opts],
      conflict_target: [:vector_store_id, :organization_id]
    )
  end

  @doc """
    Retrieves a vector_store
  """
  @spec get_vector_store(integer()) :: {:ok, VectorStore.t()} | {:error, Ecto.Changeset.t()}
  def get_vector_store(id),
    do: Repo.fetch_by(VectorStore, %{id: id})

  @doc """
  Returns the list of vector_stores
  """
  @spec list_vector_stores(map()) :: [VectorStore.t()]
  def list_vector_stores(args) do
    args
    |> Repo.list_filter_query(VectorStore, &Repo.opts_with_inserted_at/2, &filter_with/2)
    |> Repo.all()
  end

  @doc """
  Updates a vector_store.

  ## Examples

      iex> update_vector_store(vector_store, %{field: new_value})
      {:ok, %VectorStore{}}

      iex> update_vector_store(vector_store, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_vector_store(VectorStore.t(), map()) ::
          {:ok, VectorStore.t()} | {:error, Ecto.Changeset.t()}
  def update_vector_store(%VectorStore{} = vector_store, attrs) do
    vector_store
    |> VectorStore.changeset(attrs)
    |> Repo.update()
  end

  @doc """
    Deletes VectorStore
  """
  @spec delete_vector_store(VectorStore.t()) ::
          {:ok, VectorStore.t()} | {:error, Ecto.Changeset.t()}
  def delete_vector_store(%VectorStore{} = vector_store) do
    Repo.delete(vector_store)
  end

  @spec filter_with(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:vector_store_id, vector_store_id}, query ->
        from(q in query, where: q.vector_store_id == ^vector_store_id)

      _, query ->
        query
    end)
  end
end
