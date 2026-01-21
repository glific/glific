defmodule Glific.Assistants.Assistant do
  @moduledoc """
  Assistant schema
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Assistants.AssistantConfigVersion,
    Partners.Organization
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          active_config_version_id: non_neg_integer() | nil,
          organization_id: non_neg_integer() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          active_config_version:
            AssistantConfigVersion.t() | Ecto.Association.NotLoaded.t() | nil,
          config_versions: [AssistantConfigVersion.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields [
    :name,
    :organization_id
  ]
  @optional_fields [
    :description,
    :active_config_version_id
  ]

  schema "assistants" do
    field(:name, :string)
    field(:description, :string)

    belongs_to(:organization, Organization)
    belongs_to(:active_config_version, AssistantConfigVersion)
    has_many :config_versions, AssistantConfigVersion

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for updating the active_config_version_id
  """
  def set_active_config_version_changeset(assistant, attrs) do
    assistant
    |> cast(attrs, [:active_config_version_id])
    |> validate_required([:active_config_version_id])
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(assistant, attrs) do
    assistant
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
