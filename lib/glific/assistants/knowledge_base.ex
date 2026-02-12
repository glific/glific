defmodule Glific.Assistants.KnowledgeBase do
  @moduledoc """
  Knowledge base schema
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Assistants.KnowledgeBase,
    Assistants.KnowledgeBaseVersion,
    Partners.Organization
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          name: String.t() | nil,
          organization_id: non_neg_integer() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          versions: [KnowledgeBaseVersion.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields [:name, :organization_id]

  schema "knowledge_bases" do
    field(:name, :string)

    has_many(:versions, KnowledgeBaseVersion)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(KnowledgeBase.t(), map()) :: Ecto.Changeset.t()
  def changeset(knowledge_base, attrs) do
    knowledge_base
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
