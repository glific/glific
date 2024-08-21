defmodule Glific.OpenAI.VectorStore do
  @moduledoc """
  The table structure to record vector store information from Filesearch API
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo
  }

  # define all the required fields for
  @required_fields [
    :organization_id,
    :vector_store_id
  ]
  @optional_fields [
    :vector_store_name,
    :has_assistant,
    :assistant_counts
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          vector_store_id: String.t() | nil,
          vector_store_name: String.t() | nil,
          organization_id: non_neg_integer | nil,
          has_assistant: boolean() | false,
          assistant_counts: integer() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "openai_vector_store" do
    field :vector_store_id, :string
    field :vector_store_name, :string
    field :has_assistant, :boolean, default: false
    field :assistant_counts, :integer

    belongs_to :organization, Organization
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(VectorStore.t(), map()) :: Ecto.Changeset.t()
  def changeset(openai_vector_store, attrs) do
    openai_vector_store
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
  end

  @doc """
  Creates Vector Store record
  """
  @spec record_vector_store(map()) :: {:ok, VectorStore.t()} | {:error, Ecto.Changeset.t()}
  def record_vector_store(attrs) do
    %VectorStore{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
    Retrieves a vector_store record by clauses
  """
  @spec get_vector_store(map()) :: VectorStore.t() | nil
  def get_vector_store(clauses),
    do: Repo.get_by(VectorStore, clauses, skip_organization_id: true)

  @doc """
    Returns the list of vector_stores
  """
  @spec list_vector_store(map()) :: [VectorStore.t()]
  def list_vector_store(args),
    do:
      Repo.list_filter(args, VectorStore, &Repo.opts_with_inserted_at/2, &Repo.filter_with/2,
        skip_organization_id: true
      )

  @doc """
    Deletes vector store record
  """
  @spec delete_vector_store_record(VectorStore.t()) ::
          {:ok, VectorStore.t()} | {:error, Ecto.Changeset.t()}
  def delete_vector_store_record(%VectorStore{} = openai_vector_store) do
    Repo.delete(openai_vector_store, skip_organization_id: true)
  end
end
