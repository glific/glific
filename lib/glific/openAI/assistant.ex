defmodule Glific.OpenAI.Assistant do
  @moduledoc """
  The table structure to record assistant information from Filesearch API
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
    :assistant_id,
    :organization_id,
    :model,
    :description,
    :instructions
  ]
  @optional_fields [
    :vector_store_id,
    # TODO: vector_store_id null means no vector store right?
    :has_vector_store,
    # TODO: assistant name should be required
    :assistant_name
  ]
  # TODO: Advanced settings on has temperature now?
  # TODO: Need to add temperature?

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          assistant_id: String.t() | nil,
          assistant_name: String.t() | nil,
          organization_id: non_neg_integer | nil,
          has_vector_store: boolean() | true,
          vector_store_id: String.t() | nil,
          model: String.t() | nil,
          description: String.t() | nil,
          instructions: String.t() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "openai_assistant" do
    field :assistant_id, :string
    field :assistant_name, :string
    field :has_vector_store, :boolean, default: true
    # TODO: assistant - vector store might have one-many relationship
    field :vector_store_id, :string
    field :model, :string
    field :description, :string
    field :instructions, :string

    belongs_to :organization, Organization
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Assistant.t(), map()) :: Ecto.Changeset.t()
  def changeset(openai_assistant, attrs) do
    openai_assistant
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
  end

  @doc """
  Creates an assistant record
  """
  @spec record_assistant(map()) :: {:ok, Assistant.t()} | {:error, Ecto.Changeset.t()}
  def record_assistant(attrs) do
    %Assistant{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  # TODO Put both migrations in one file
  # TODO: why skip_organization_id??
  @doc """
    Retrieves an assistant record by clauses
  """
  @spec get_assistant(map()) :: Assistant.t() | nil
  def get_assistant(clauses),
    do: Repo.get_by(Assistant, clauses, skip_organization_id: true)

  @doc """
    Returns the list of assistants
  """
  @spec list_assistant(map()) :: [Assistant.t()]
  def list_assistant(args),
    do:
      Repo.list_filter(args, Assistant, &Repo.opts_with_inserted_at/2, &Repo.filter_with/2,
        skip_organization_id: true
      )

  # TODO: function name refactoring (all functions check)
  @doc """
    Deletes assistant record
  """
  @spec delete_assistant_record(Assistant.t()) ::
          {:ok, Assistant.t()} | {:error, Ecto.Changeset.t()}
  def delete_assistant_record(%Assistant{} = openai_assistant) do
    Repo.delete(openai_assistant, skip_organization_id: true)
  end
end
