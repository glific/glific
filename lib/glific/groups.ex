defmodule Glific.Groups do
  @moduledoc """
  The Groups context.
  """
  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{Repo, Users.User}

  alias Glific.Groups.{ContactGroup, Group, UserGroup}

  @spec has_permission?(non_neg_integer) :: boolean()
  defp has_permission?(id) do
    if Repo.skip_permission?() == true do
      true
    else
      group =
        Group
        |> Ecto.Queryable.to_query()
        |> Repo.add_permission(&Groups.add_permission/2)
        |> where([g], g.id == ^id)
        |> select([g], g.id)
        |> Repo.one()

      if group == nil,
        do: false,
        else: true
    end
  end

  @doc """
  Add permissioning specific to groups, in this case we want to restrict the visibility of
  groups that the user can see
  """
  @spec add_permission(Ecto.Query.t(), User.t()) :: Ecto.Query.t()
  def add_permission(query, user) do
    query
    |> join(:inner, [g], ug in UserGroup, as: :ug, on: ug.user_id == ^user.id)
    |> where([g, ug: ug], g.id == ug.group_id)
  end

  @doc """
  Returns the list of groups.

  ## Examples

      iex> list_groups()
      [%Group{}, ...]

  """
  @spec list_groups(map()) :: [Group.t()]
  def list_groups(%{filter: %{organization_id: _organization_id}} = args) do
    args
    |> Repo.list_filter_query(Group, &Repo.opts_with_label/2, &Repo.filter_with/2)
    |> Repo.add_permission(&Groups.add_permission/2)
    |> Repo.all()
  end

  @doc """
  Return the count of groups, using the same filter as list_groups
  """
  @spec count_groups(map()) :: integer
  def count_groups(%{filter: %{organization_id: _organization_id}} = args) do
    args
    |> Repo.list_filter_query(Group, nil, &Repo.filter_with/2)
    |> Repo.add_permission(&Groups.add_permission/2)
    |> Repo.aggregate(:count)
  end

  @doc """
  Return the count of group contacts
  """
  @spec contacts_count(map()) :: integer
  def contacts_count(%{id: group_id}) do
    ContactGroup
    |> where([cg], cg.group_id == ^group_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Return the count of group users
  """
  @spec users_count(map()) :: integer
  def users_count(%{id: group_id}) do
    UserGroup
    |> where([cg], cg.group_id == ^group_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets a single group.

  Raises `Ecto.NoResultsError` if the Group does not exist.

  ## Examples

      iex> get_group!(123)
      %Group{}

      iex> get_group!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_group!(integer) :: Group.t()
  def get_group!(id) do
    Group
    |> Ecto.Queryable.to_query()
    |> Repo.add_permission(&Groups.add_permission/2)
    |> Repo.get!(id)
  end

  @doc """
  Creates a group.

  ## Examples

      iex> create_group(%{field: value})
      {:ok, %Group{}}

      iex> create_group(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_group(map()) :: {:ok, Group.t()} | {:error, Ecto.Changeset.t()}
  def create_group(attrs \\ %{}) do
    %Group{}
    |> Group.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a group.

  ## Examples

      iex> update_group(group, %{field: new_value})
      {:ok, %Group{}}

      iex> update_group(group, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_group(Group.t(), map()) :: {:ok, Group.t()} | {:error, Ecto.Changeset.t()}
  def update_group(%Group{} = group, attrs) do
    if has_permission?(group.id) do
      group
      |> Group.changeset(attrs)
      |> Repo.update()
    else
      raise "Permission denied"
    end
  end

  @doc """
  Deletes a group.

  ## Examples

      iex> delete_group(group)
      {:ok, %Group{}}

      iex> delete_group(group)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_group(Group.t()) :: {:ok, Group.t()} | {:error, Ecto.Changeset.t()}
  def delete_group(%Group{} = group) do
    if has_permission?(group.id),
      do: Repo.delete(group),
      else: raise("Permission denied")
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking group changes.

  ## Examples

      iex> change_group(group)
      %Ecto.Changeset{data: %Group{}}

  """
  @spec change_group(Group.t(), map()) :: Ecto.Changeset.t()
  def change_group(%Group{} = group, attrs \\ %{}) do
    Group.changeset(group, attrs)
  end

  @doc """
  Creates a contact group.

  ## Examples

      iex> create_contact_group(%{field: value})
      {:ok, %Contact{}}

      iex> create_contact_group(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_contact_group(map()) :: {:ok, ContactGroup.t()} | {:error, Ecto.Changeset.t()}
  def create_contact_group(attrs \\ %{}) do
    # Merge default values if not present in attributes
    %ContactGroup{}
    |> ContactGroup.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Delete group contacts
  """
  @spec delete_group_contacts_by_ids(integer, []) :: {integer(), nil | [term()]}
  def delete_group_contacts_by_ids(group_id, contact_ids) do
    fields = {{:group_id, group_id}, {:contact_id, contact_ids}}
    Repo.delete_relationships_by_ids(ContactGroup, fields)
  end

  @doc """
  Delete contact groups
  """
  @spec delete_contact_groups_by_ids(integer, []) :: {integer(), nil | [term()]}
  def delete_contact_groups_by_ids(contact_id, group_ids) do
    fields = {{:contact_id, contact_id}, {:group_id, group_ids}}
    Repo.delete_relationships_by_ids(ContactGroup, fields)
  end

  @doc """
  Creates a user group.

  ## Examples

      iex> create_user_group(%{field: value})
      {:ok, %User{}}

      iex> create_user_group(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_user_group(map()) :: {:ok, UserGroup.t()} | {:error, Ecto.Changeset.t()}
  def create_user_group(attrs \\ %{}) do
    %UserGroup{}
    |> UserGroup.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Delete group users
  """
  @spec delete_group_users_by_ids(integer, []) :: {integer(), nil | [term()]}
  def delete_group_users_by_ids(group_id, user_ids) do
    fields = {{:group_id, group_id}, {:user_id, user_ids}}
    Repo.delete_relationships_by_ids(UserGroup, fields)
  end

  @doc """
  Delete user groups
  """
  @spec delete_user_groups_by_ids(integer, []) :: {integer(), nil | [term()]}
  def delete_user_groups_by_ids(user_id, group_ids) do
    fields = {{:user_id, user_id}, {:group_id, group_ids}}
    Repo.delete_relationships_by_ids(UserGroup, fields)
  end

  @doc """
  Updates user groups entries
  """
  @spec update_user_groups(map()) :: :ok
  def update_user_groups(%{
        user_id: user_id,
        group_ids: group_ids,
        organization_id: organization_id
      }) do
    user_group_ids =
      UserGroup
      |> where([ug], ug.user_id == ^user_id)
      |> select([ug], ug.group_id)
      |> Repo.all()

    group_ids = Enum.map(group_ids, fn x -> String.to_integer(x) end)
    add_group_ids = group_ids -- user_group_ids
    delete_group_ids = user_group_ids -- group_ids

    new_group_entries =
      Enum.map(add_group_ids, fn group_id ->
        %{user_id: user_id, group_id: group_id, organization_id: organization_id}
      end)

    UserGroup
    |> Repo.insert_all(new_group_entries)

    UserGroup
    |> where([ug], ug.user_id == ^user_id and ug.group_id in ^delete_group_ids)
    |> Repo.delete_all()

    :ok
  end
end
