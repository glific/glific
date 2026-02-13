defmodule Glific.Assistants.Assistant do
  @moduledoc """
  Assistant schema
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Partners.Organization
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          kaapi_uuid: String.t() | nil,
          assistant_display_id: String.t() | nil,
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
    :active_config_version_id,
    :kaapi_uuid,
    :assistant_display_id
  ]

  schema "assistants" do
    field(:name, :string)
    field(:description, :string)
    field(:kaapi_uuid, :string)
    field(:assistant_display_id, :string)

    belongs_to(:organization, Organization)
    belongs_to(:active_config_version, AssistantConfigVersion)
    has_many :config_versions, AssistantConfigVersion

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for updating the active_config_version_id
  """
  @spec set_active_config_version_changeset(Assistant.t(), map()) :: Ecto.Changeset.t()
  def set_active_config_version_changeset(assistant, attrs) do
    assistant
    |> cast(attrs, [:active_config_version_id])
    |> validate_required([:active_config_version_id])
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Assistant.t(), map()) :: Ecto.Changeset.t()
  def changeset(assistant, attrs) do
    assistant
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> add_display_id()
    |> unique_constraint(:assistant_display_id)
  end

  defp add_display_id(changeset) do
    case get_field(changeset, :assistant_display_id) do
      nil -> put_change(changeset, :assistant_display_id, generate_display_id())
      _ -> changeset
    end
  end

  # Generate an OpenAI-style assistant ID
  # Format: asst_ followed by 24 random alphanumeric characters
  @spec generate_display_id() :: String.t()
  defp generate_display_id do
    random_string =
      24
      |> :crypto.strong_rand_bytes()
      |> Base.encode32(case: :lower, padding: false)
      |> binary_part(0, 24)

    "asst_#{random_string}"
  end
end
