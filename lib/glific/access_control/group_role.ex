defmodule Glific.AccessControl.GroupRole do
  @moduledoc """
  A pipe for managing the role groups
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    AccessControl.Role,
    AccessControl.UserRole,
    Groups.Group,
    Partners.Organization,
    Repo,
    Users.User
  }

  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [:role_id, :group_id, :organization_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          role: Role.t() | Ecto.Association.NotLoaded.t() | nil,
          group: Group.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "group_roles" do
    belongs_to :role, Role
    belongs_to :group, Group
    belongs_to :organization, Organization
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(GroupRole.t(), map()) :: Ecto.Changeset.t()
  def changeset(role_group, attrs) do
    role_group
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(@required_fields)
    |> foreign_key_constraint(:role_id)
    |> foreign_key_constraint(:group_id)
  end

  @doc """
  Creates a access control.
  ## Examples
      iex> create_group_role(%{field: value})
      {:ok, %GroupRole{}}
      iex> create_group_role(%{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_group_role(map()) :: {:ok, GroupRole.t()} | {:error, Ecto.Changeset.t()}
  def create_group_role(attrs \\ %{}) do
    %GroupRole{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update group roles based on add_role_ids and delete_role_ids and return number_deleted as integer and roles added as access_controls
  """
  @spec update_group_roles(map()) :: map()
  def update_group_roles(
        %{
          group_id: group_id,
          add_role_ids: add_role_ids
        } = attrs
      ) do
    access_controls =
      Enum.reduce(
        add_role_ids,
        [],
        fn role_id, acc ->
          case create_group_role(Map.merge(attrs, %{role_id: role_id, group_id: group_id})) do
            {:ok, access_control} -> [access_control | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} =
      if Map.has_key?(attrs, :delete_role_ids),
        do: delete_group_roles_by_role_ids(group_id, attrs.delete_role_ids),
        else: {0, attrs}

    %{
      number_deleted: number_deleted,
      access_controls: access_controls
    }
  end

  @doc """
  Delete group roles
  """
  @spec delete_group_roles_by_role_ids(integer, list()) :: {integer(), nil | [term()]}
  def delete_group_roles_by_role_ids(group_id, role_ids) do
    fields = {{:group_id, group_id}, {:role_id, role_ids}}
    Repo.delete_relationships_by_ids(GroupRole, fields)
  end

  @doc """
  Filtering entity object based on user role
  """
  @spec check_access(Ecto.Query.t(), User.t()) :: Ecto.Query.t()
  def check_access(entity_list, user) do
    sub_query =
      GroupRole
      |> select([rf], rf.group_id)
      |> join(:inner, [rf], ru in UserRole, as: :ru, on: ru.role_id == rf.role_id)
      |> where([rf, ru: ru], ru.user_id == ^user.id)

    entity_list
    |> where(
      [f],
      f.id in subquery(sub_query)
    )
  end
end
