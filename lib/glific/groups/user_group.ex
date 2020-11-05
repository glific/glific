defmodule Glific.Groups.UserGroup do
  @moduledoc """
  A pipe for managing the user groups
  """

  alias Glific.{
    Groups.Group,
    Groups.UserGroup,
    Users.User,
    Partners.Organization
  }

  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [:user_id, :group_id, :organization_id]
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          group: Group.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "users_groups" do
    belongs_to :user, User
    belongs_to :group, Group
    belongs_to :organization, Organization
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(UserGroup.t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:user_id, :group_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:group_id)
  end
end
