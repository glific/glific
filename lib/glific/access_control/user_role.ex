defmodule Glific.AccessControl.UserRole do
  @moduledoc """
  A pipe for managing the user roles
  """

  alias Glific.{
    AccessControl.Role,
    Partners.Organization,
    Users.User
  }

  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [:user_id, :role_id, :organization_id]
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          role: Role.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "users_roles" do
    belongs_to :user, User
    belongs_to :role, Role
    belongs_to :organization, Organization
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(UserRole.t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:user_id, :role_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:role_id)
  end
end
