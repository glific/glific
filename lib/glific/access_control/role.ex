defmodule Glific.AccessControl.Role do
  @moduledoc """
  The minimal wrapper for the base Access Control Role structure
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    AccessControl.Permission,
    Partners.Organization
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          description: String.t() | nil,
          label: String.t() | nil,
          is_reserved: boolean(),
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }
  schema "roles" do
    field :description, :string
    field :is_reserved, :boolean, default: false
    field :label, :string

    belongs_to :organization, Organization
    many_to_many :permissions, Permission, join_through: "role_permissions", on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Role.t(), map()) :: Ecto.Changeset.t()
  def changeset(role, attrs) do
    role
    |> cast(attrs, [:label, :description, :is_reserved, :organization_id])
    |> validate_required([:label, :description, :is_reserved, :organization_id])
    |> unique_constraint([:label, :organization_id])
  end
end
