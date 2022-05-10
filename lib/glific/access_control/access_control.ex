defmodule Glific.AccessControl do
  @moduledoc """
  The minimal wrapper for the base Access Control structure
  """
  use Ecto.Schema

  alias Glific.{
    AccessControl.Role,
    Enums.EntityType,
    Partners.Organization
  }

  alias __MODULE__
  import Ecto.Changeset

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          entity_id: non_neg_integer | nil,
          entity_type: EntityType | nil,
          role_id: non_neg_integer | nil,
          role: Role.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }
  schema "access_control" do
    field :entity_id, :id
    field :entity_type, EntityType

    belongs_to :role, Role
    belongs_to :organization, Organization
    timestamps()
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(AccessControl.t(), map()) :: Ecto.Changeset.t()
  def changeset(permission, attrs) do
    permission
    |> cast(attrs, [:entity])
    |> validate_required([:entity])
  end
end
