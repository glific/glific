defmodule Glific.Assistants.KnowledgeBaseVersion do
  @moduledoc """
  Knowledge base version schema
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Glific.{
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBase,
    Assistants.KnowledgeBaseVersion,
    Enums.KnowledgeBaseStatus,
    Partners.Organization,
    Repo
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          knowledge_base_id: non_neg_integer() | nil,
          knowledge_base: KnowledgeBase.t() | Ecto.Association.NotLoaded.t() | nil,
          version_number: non_neg_integer() | nil,
          files: map() | nil,
          size: non_neg_integer(),
          status: KnowledgeBaseStatus.t(),
          organization_id: non_neg_integer() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          kaapi_job_id: String.t() | nil,
          llm_service_id: String.t() | nil,
          assistant_config_versions:
            [AssistantConfigVersion.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields [
    :knowledge_base_id,
    :organization_id,
    :files,
    :status,
    :llm_service_id
  ]
  @optional_fields [
    :size,
    :version_number,
    :kaapi_job_id
  ]

  schema "knowledge_base_versions" do
    field(:version_number, :integer)
    field(:files, :map)
    field(:size, :integer, default: 0)

    field(:status, KnowledgeBaseStatus, default: :in_progress)

    field(:kaapi_job_id, :string)
    field(:llm_service_id, :string)

    belongs_to(:organization, Organization)
    belongs_to(:knowledge_base, KnowledgeBase)

    many_to_many(
      :assistant_config_versions,
      AssistantConfigVersion,
      join_through: "assistant_config_version_knowledge_base_versions"
    )

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(KnowledgeBaseVersion.t(), map()) :: Ecto.Changeset.t()
  def changeset(knowledge_base_version, attrs) do
    knowledge_base_version
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> assoc_constraint(:knowledge_base)
    |> unique_constraint([:knowledge_base_id, :version_number])
  end

  @doc """
  Fetches the knowledge base version
  """
  @spec get_knowledge_base_version(integer()) ::
          {:ok, KnowledgeBaseVersion.t()} | {:error, [String.t()]}
  def get_knowledge_base_version(kb_id) do
    KnowledgeBaseVersion
    |> where([kbv], kbv.knowledge_base_id == ^kb_id)
    |> order_by([kbv], desc: kbv.version_number)
    |> limit(1)
    |> Repo.one()
    |> then(fn
      nil -> {:error, ["KnowledgeBaseVersion", "Resource not found"]}
      kb_version -> {:ok, kb_version}
    end)
  end

  @doc """
  Fetches the knowledge base version by llm_service_id
  """
  @spec get_by_version_id(String.t()) ::
          {:ok, KnowledgeBaseVersion.t()} | {:error, [String.t()]}
  def get_by_version_id(knowledge_base_version_id) do
    Repo.fetch_by(KnowledgeBaseVersion, id: knowledge_base_version_id)
  end
end
