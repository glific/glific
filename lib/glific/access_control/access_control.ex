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

  @required_fields [:entity_id, :entity_type, :role_id, :organization_id]

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
    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(AccessControl.t(), map()) :: Ecto.Changeset.t()
  def changeset(access, attrs) do
    access
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:entity_id, :entity_type, :role_id, :organization_id])
  end
end
