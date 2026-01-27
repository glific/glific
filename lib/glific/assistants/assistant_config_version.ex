defmodule Glific.Assistants.AssistantConfigVersion do
  @moduledoc """
  Assistant configuration version schema
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBaseVersion,
    Enums.AssistantConfigVersionStatus,
    Partners.Organization
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer(),
          assistant_id: non_neg_integer(),
          assistant: Assistant.t() | Ecto.Association.NotLoaded.t() | nil,
          version_number: non_neg_integer(),
          description: String.t() | nil,
          prompt: String.t(),
          provider: String.t(),
          model: String.t(),
          settings: map(),
          kaapi_uuid: String.t(),
          status: AssistantConfigVersionStatus.t(),
          failure_reason: String.t() | nil,
          deleted_at: DateTime.t() | nil,
          organization_id: non_neg_integer(),
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          knowledge_base_versions: [KnowledgeBaseVersion.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields [
    :assistant_id,
    :provider,
    :status,
    :model,
    :kaapi_uuid,
    :prompt,
    :settings,
    :organization_id
  ]

  @optional_fields [
    :description,
    :failure_reason,
    :version_number,
    :deleted_at
  ]

  schema "assistant_config_versions" do
    field(:version_number, :integer)
    field(:description, :string)
    field(:prompt, :string)

    field(:provider, :string, default: "openai")
    field(:model, :string)
    field(:kaapi_uuid, :string)

    field(:settings, :map, default: %{})
    field(:status, AssistantConfigVersionStatus, default: :in_progress)
    field(:failure_reason, :string)
    field(:deleted_at, :utc_datetime_usec)

    belongs_to(:assistant, Assistant)
    belongs_to(:organization, Organization)

    many_to_many(
      :knowledge_base_versions,
      KnowledgeBaseVersion,
      join_through: "assistant_config_version_knowledge_base_versions"
    )

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(AssistantConfigVersion.t(), map()) :: Ecto.Changeset.t()
  def changeset(config_version, attrs) do
    config_version
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> assoc_constraint(:assistant)
    |> unique_constraint(
      [:assistant_id, :version_number],
      name: :assistant_config_versions_assistant_id_version_number_index
    )
  end
end
