defmodule Glific.Assistants.Assistant do
  @moduledoc """
  Assistant schema
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Glific.{
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Partners.Organization,
    Repo
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          kaapi_uuid: String.t() | nil,
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
    :organization_id,
    :kaapi_uuid
  ]
  @optional_fields [
    :description,
    :active_config_version_id
  ]

  schema "assistants" do
    field(:name, :string)
    field(:description, :string)
    field(:kaapi_uuid, :string)

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
  Creates an assistant
  """
  @spec create_assistant(map()) :: {:ok, Assistant.t()} | {:error, Ecto.Changeset.t()}
  def create_assistant(attrs) do
    %Assistant{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates active config
  """
  @spec update_assistant_active_config(non_neg_integer(), non_neg_integer()) ::
          {:ok, Assistant.t()} | {:error, Ecto.Changeset.t()}
  def update_assistant_active_config(assistant_id, config_version_id) do
    assistant = Repo.get!(Assistant, assistant_id)

    assistant
    |> Ecto.Changeset.change(%{
      active_config_version_id: config_version_id
    })
    |> Repo.update()
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Assistant.t(), map()) :: Ecto.Changeset.t()
  def changeset(assistant, attrs) do
    assistant
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
