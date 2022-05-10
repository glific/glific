defmodule Glific.AccessControls do
  @moduledoc """
  The AccessControl context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    AccessControl,
    AccessControl.Permission,
    AccessControl.Role,
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

      {:entity_type, entity_type}, query ->
        from(q in query, where: q.entity_type == ^entity_type)

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

  @doc """
  Creates a access control.

  ## Examples

      iex> create_access_control(%{field: value})
      {:ok, %Role{}}

      iex> create_access_control(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_access_control(map()) :: {:ok, AccessControl.t()} | {:error, Ecto.Changeset.t()}
  def create_access_control(attrs \\ %{}) do
    %AccessControl{}
    |> AccessControl.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a access control.

  ## Examples

      iex> update_access_control(access_control, %{field: new_value})
      {:ok, %Permission{}}

      iex> update_access_control(access_control, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_access_control(AccessControl.t(), map()) ::
          {:ok, AccessControl.t()} | {:error, Ecto.Changeset.t()}
  def update_access_control(%AccessControl{} = access_control, attrs) do
    access_control
    |> AccessControl.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  updates
  """
  @spec update_control_access(map()) :: map()
  def update_control_access(
        %{
          entity_id: entity_id,
          add_role_ids: add_role_ids,
          delete_role_ids: delete_role_ids
        } = attrs
      ) do
    access_controls =
      Enum.reduce(
        add_role_ids,
        [],
        fn role_id, acc ->
          case create_access_control(Map.put(attrs, :role_id, role_id)) do
            {:ok, access_control} -> [access_control | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} = delete_access_control_by_role_ids(entity_id, delete_role_ids)

    %{
      number_deleted: number_deleted,
      access_controls: access_controls
    }
  end

  @doc """
  Delete group contacts

  """
  @spec delete_access_control_by_role_ids(integer, list()) :: {integer(), nil | [term()]}
  def delete_access_control_by_role_ids(entity_id, role_ids) do
    fields = {{:entity_id, entity_id}, {:role_id, role_ids}}
    Repo.delete_relationships_by_ids(AccessControl, fields)
  end

  @doc """
  Deletes a access control.

  ## Examples

      iex> delete_access_control(access_control)
      {:ok, %AccessControl{}}

      iex> delete_access_control(access_control)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_access_control(AccessControl.t()) ::
          {:ok, AccessControl.t()} | {:error, Ecto.Changeset.t()}
  def delete_access_control(%AccessControl{} = access_control) do
    Repo.delete(access_control)
  end

  @doc """
  Returns the list of access controls.

  ## Examples

      iex> list_access_controls()
      [%Role{}, ...]

  """
  @spec list_access_controls(map()) :: [AccessControl.t()]
  def list_access_controls(args),
    do: Repo.list_filter(args, AccessControl, &Repo.opts_with_label/2, &filter_with/2)

  @doc """
  Return the count of access controls, using the same filter as list_roles
  """
  @spec count_access_controls(map()) :: integer
  def count_access_controls(args), do: Repo.count_filter(args, AccessControl, &filter_with/2)
end
