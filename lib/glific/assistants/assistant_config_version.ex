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
    Enums.AssistantConfigVersionBumpType,
    Enums.AssistantConfigVersionStatus,
    Partners.Organization
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          assistant_id: non_neg_integer() | nil,
          assistant: Assistant.t() | Ecto.Association.NotLoaded.t() | nil,
          major_version: non_neg_integer() | nil,
          minor_version: non_neg_integer() | nil,
          bump_type: AssistantConfigVersionBumpType.t(),
          kaapi_version_number: non_neg_integer() | nil,
          description: String.t() | nil,
          prompt: String.t() | nil,
          provider: String.t() | nil,
          model: String.t() | nil,
          settings: map(),
          status: AssistantConfigVersionStatus.t(),
          failure_reason: String.t() | nil,
          deleted_at: DateTime.t() | nil,
          organization_id: non_neg_integer() | nil,
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
    :prompt,
    :settings,
    :organization_id
  ]

  @optional_fields [
    :description,
    :failure_reason,
    :major_version,
    :minor_version,
    :bump_type,
    :kaapi_version_number,
    :deleted_at
  ]

  schema "assistant_config_versions" do
    field(:major_version, :integer, read_after_writes: true)
    field(:minor_version, :integer, read_after_writes: true)
    field(:bump_type, AssistantConfigVersionBumpType, default: :minor)
    field(:kaapi_version_number, :integer)
    field(:description, :string)
    field(:prompt, :string)

    field(:provider, :string, default: "openai")
    field(:model, :string)

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
      [:assistant_id, :major_version, :minor_version],
      name: :assistant_config_versions_assistant_id_major_version_minor_vers
    )
  end

  @doc "Display label for a config version, e.g. `\"1.3\"`."
  @spec version_label(map()) :: String.t() | nil
  def version_label(%{major_version: major, minor_version: minor})
      when not is_nil(major) and not is_nil(minor),
      do: "#{major}.#{minor}"

  def version_label(_config_version), do: nil
end
