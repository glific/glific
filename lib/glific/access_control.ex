defmodule Glific.AccessControl do
  @moduledoc """
  The AccessControl context.
  """

  import Ecto.Query, warn: false
  import GlificWeb.Gettext

  alias Glific.{
    AccessControl.FlowRole,
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
  def list_roles(args) do
    check_fun_with_flag_toggle?(args.organization_id)
    |> hide_organization_roles(args)
    |> Repo.list_filter(Role, &Repo.opts_with_label/2, &filter_with/2)
  end

  @spec hide_organization_roles(boolean(), map()) :: map()
  defp hide_organization_roles(true, args), do: args

  defp hide_organization_roles(false, %{filter: _filter} = args) do
    args.filter
    |> Map.merge(%{is_reserved: true})
    |> then(&Map.put(args, :filter, &1))
  end

  defp hide_organization_roles(false, args), do: Map.put(args, :filter, %{is_reserved: true})

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
  def count_access_roles(args) do
    check_fun_with_flag_toggle?(args.organization_id)
    |> hide_organization_roles(args)
    |> Repo.count_filter(Role, &filter_with/2)
  end

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
  Common function to filtering entity objects based on user role, fun_with_flag flag and entity type
  """
  @spec check_access(Ecto.Query.t(), atom()) :: Ecto.Query.t()
  def check_access(entity_list, entity_type) do
    user = Repo.get_current_user()

    if check_fun_with_flag_toggle?(user.organization_id) and
         has_minimum_permissions(user),
       do: do_check_access(entity_list, entity_type, user),
       else: entity_list
  end

  @spec has_minimum_permissions(User.t() | nil) :: boolean()
  defp has_minimum_permissions(nil), do: false

  defp has_minimum_permissions(user) do
    !Enum.any?(user.roles, fn role -> role in [:admin, :glific_admin, :staff] end)
  end

  @doc """
  check fun_with_flag toggle for an organization and returns boolean value
  """
  @spec check_fun_with_flag_toggle?(non_neg_integer()) :: boolean()
  def check_fun_with_flag_toggle?(organization_id) do
    FunWithFlags.enabled?(
      :roles_and_permission,
      for: %{organization_id: organization_id}
    )
  end

  @doc """
  Common function to filtering entity objects based on user role, fun_with_flag flag and entity type
  """
  @spec do_check_access(Ecto.Query.t(), atom(), User.t()) :: Ecto.Query.t() | {:error, String.t()}
  def do_check_access(entity_list, entity_type, user) do
    # organization_contact_id = Partners.organization_contact_id(user.organization_id)

    entity_type
    |> case do
      :flow -> FlowRole.check_access(entity_list, user)
      _ -> {:error, dgettext("errors", "Invalid BSP provider")}
    end
  end
end
