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

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          role: Role.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "user_roles" do
    belongs_to(:user, User)
    belongs_to(:role, Role)
    belongs_to(:organization, Organization)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(UserRole.t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:user_id, :role_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:role_id)
  end

  @doc """
  Creates a access control.
  ## Examples
      iex> create_user_role(%{field: value})
      {:ok, %UserRole{}}
      iex> create_user_role(%{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_user_role(map()) :: {:ok, UserRole.t()} | {:error, Ecto.Changeset.t()}
  def create_user_role(attrs \\ %{}) do
    %UserRole{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update user roles based on add_role_ids and delete_role_ids and return number_deleted as integer and roles added as access_controls
  """
  @spec update_user_roles(map()) :: map()
  def update_user_roles(
        %{
          user_id: user_id,
          add_role_ids: add_role_ids,
          delete_role_ids: delete_role_ids
        } = attrs
      ) do
    access_controls =
      Enum.reduce(
        add_role_ids,
        [],
        fn role_id, acc ->
          case create_user_role(Map.merge(attrs, %{role_id: role_id, user_id: user_id})) do
            {:ok, access_control} -> [access_control | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} = delete_user_roles_by_role_ids(user_id, delete_role_ids)

    %{
      number_deleted: number_deleted,
      access_controls: access_controls
    }
  end

  @doc """
  Delete user roles
  """
  @spec delete_user_roles_by_role_ids(integer, list()) :: {integer(), nil | [term()]}
  def delete_user_roles_by_role_ids(user_id, role_ids) do
    fields = {{:user_id, user_id}, {:role_id, role_ids}}
    Repo.delete_relationships_by_ids(UserRole, fields)
  end
end
