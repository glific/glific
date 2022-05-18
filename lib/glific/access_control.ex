defmodule Glific.AccessControl do
  @moduledoc """
  The AccessControl context.
  """

  import Ecto.Query, warn: false
  import GlificWeb.Gettext

  alias Glific.{
    AccessControl.Permission,
    AccessControl.Role,
    AccessControl.RoleFlow,
    Repo
  }

  @doc """
  Returns the list of roles.

  ## Examples

      iex> list_roles()
      [%Role{}, ...]

  """
  @spec list_roles(map()) :: [Role.t()]
  def list_roles(args), do: Repo.list_filter(args, Role, &Repo.opts_with_label/2, &filter_with/2)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:description, description}, query ->
        from(q in query, where: ilike(q.description, ^"%#{description}%"))

      {:is_reserved, is_reserved}, query ->
        from(q in query, where: q.is_reserved == ^is_reserved)

      _, query ->
        query
    end)
  end

  @doc """
  Return the count of roles, using the same filter as list_roles
  """
  @spec count_access_roles(map()) :: integer
  def count_access_roles(args), do: Repo.count_filter(args, Role, &filter_with/2)

  @doc """
  Gets a single role.

  Raises `Ecto.NoResultsError` if the Role does not exist.

  ## Examples

      iex> get_role!(123)
      %Role{}

      iex> get_role!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_role!(integer) :: Role.t()
  def get_role!(id), do: Repo.get!(Role, id)

  @doc """
  Creates a role.

  ## Examples

      iex> create_role(%{field: value})
      {:ok, %Role{}}

      iex> create_role(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_role(map()) :: {:ok, Role.t()} | {:error, Ecto.Changeset.t()}
  def create_role(attrs \\ %{}) do
    %Role{}
    |> Role.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a role.

  ## Examples

      iex> update_role(role, %{field: new_value})
      {:ok, %Role{}}

      iex> update_role(role, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_role(Role.t(), map()) :: {:ok, Role.t()} | {:error, Ecto.Changeset.t()}
  def update_role(%Role{} = role, attrs) do
    role
    |> Role.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a role.

  ## Examples

      iex> delete_role(role)
      {:ok, %Role{}}

      iex> delete_role(role)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_role(Role.t()) :: {:ok, Role.t()} | {:error, Ecto.Changeset.t()}
  def delete_role(%Role{} = role) do
    Repo.delete(role)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking role changes.

  ## Examples

      iex> change_role(role)
      %Ecto.Changeset{data: %Role{}}

  """
  @spec change_role(Role.t()) :: Ecto.Changeset.t()
  def change_role(%Role{} = role, attrs \\ %{}) do
    Role.changeset(role, attrs)
  end

  @doc """
  Returns the list of permissions.

  ## Examples

      iex> list_permissions()
      [%Permission{}, ...]

  """
  @spec list_permissions :: [Permission.t()]
  def list_permissions do
    Repo.all(Permission)
  end

  @doc """
  Gets a single permission.

  Raises `Ecto.NoResultsError` if the Permission does not exist.

  ## Examples

      iex> get_permission!(123)
      %Permission{}

      iex> get_permission!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_permission!(integer) :: Permission.t()
  def get_permission!(id), do: Repo.get!(Permission, id)

  @doc """
  Creates a permission.

  ## Examples

      iex> create_permission(%{field: value})
      {:ok, %Permission{}}

      iex> create_permission(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_permission(map()) :: {:ok, Permission.t()} | {:error, Ecto.Changeset.t()}
  def create_permission(attrs \\ %{}) do
    %Permission{}
    |> Permission.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a permission.

  ## Examples

      iex> update_permission(permission, %{field: new_value})
      {:ok, %Permission{}}

      iex> update_permission(permission, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_permission(Permission.t(), map()) ::
          {:ok, Permission.t()} | {:error, Ecto.Changeset.t()}
  def update_permission(%Permission{} = permission, attrs) do
    permission
    |> Permission.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a permission.

  ## Examples

      iex> delete_permission(permission)
      {:ok, %Permission{}}

      iex> delete_permission(permission)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_permission(Permission.t()) :: {:ok, Permission.t()} | {:error, Ecto.Changeset.t()}
  def delete_permission(%Permission{} = permission) do
    Repo.delete(permission)
  end

  @doc """

  Returns an `%Ecto.Changeset{}` for tracking permission changes.

  ## Examples

      iex> change_permission(permission)
      %Ecto.Changeset{data: %Permission{}}

  """
  @spec change_permission(Permission.t()) :: Ecto.Changeset.t()
  def change_permission(%Permission{} = permission, attrs \\ %{}) do
    Permission.changeset(permission, attrs)
  end

  def check_access(entity_list, entity_type) do
    user = Repo.get_current_user()

    if check_fun_with_flag_toggle?(user.organization_id) and
         user.roles not in [:admin, :glific_admin, :staff],
       do: do_check_access(entity_list, entity_type, user),
       else: entity_list
  end

  defp check_fun_with_flag_toggle?(organization_id) do
    FunWithFlags.enabled?(
      :roles_and_permission,
      for: %{organization_id: organization_id}
    )
  end

  def do_check_access(entity_list, entity_type, user) do
    # organization_contact_id = Partners.organization_contact_id(user.organization_id)

    entity_type
    |> case do
      :flow -> RoleFlow.check_access(entity_list, user)
      _ -> {:error, dgettext("errors", "Invalid BSP provider")}
    end
  end
end
