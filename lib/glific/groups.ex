defmodule Glific.Groups do
  @moduledoc """
  The Groups context.
  """
  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    AccessControl,
    AccessControl.GroupRole,
    Contacts.Contact,
    Repo,
    Users.User
  }

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
  @spec list_groups(map(), boolean()) :: [Group.t()]
  def list_groups(args, skip_permission \\ false) do
    args
    |> Repo.list_filter_query(Group, &Repo.opts_with_label/2, &Repo.filter_with/2)
    |> AccessControl.check_access(:group)
    |> Repo.add_permission(&Groups.add_permission/2, skip_permission)
    |> Repo.all()
  end

  @doc """
  Returns the list of groups.

  ## Examples

      iex> list_organizations_groups()
      [%Group{}, ...]

  """
  @spec list_organizations_groups(map()) :: [Group.t()]
  def list_organizations_groups(args) do
    {:ok, org_id} = Glific.parse_maybe_integer(args.id)

    %{organization_id: org_id}
    |> Repo.list_filter_query(Group, &Repo.opts_with_label/2, &Repo.filter_with/2)
    |> Repo.add_permission(&Groups.add_permission/2, true)
    |> Repo.all(organization_id: org_id)
  end

  @doc """
  Return the count of groups, using the same filter as list_groups
  """
  @spec count_groups(map()) :: integer
  def count_groups(args) do
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
    |> where([g], g.id == ^id)
    |> Repo.add_permission(&Groups.add_permission/2)
    |> Repo.one!()
  end

  @doc """
  Exporting collection membership details
  """
  @spec export_collection(integer) :: map()
  def export_collection(group_id) do
    result =
      ContactGroup
      |> join(:inner, [cg], c in Contact, as: :c, on: cg.contact_id == c.id)
      |> where([cg], cg.group_id == ^group_id)
      |> select([c: c], [c.name, c.phone])
      |> Repo.all()
      |> Enum.reduce("Name,Phone\r\n", fn [name, phone], acc ->
        acc <> "#{name},#{phone}\r\n"
      end)

    %{status: result}
  end

  @doc """
  Get group by group name.
  Create the group if it does not exist
  """
  @spec get_or_create_group_by_label(String.t(), non_neg_integer) :: {:ok, Group.t()} | nil
  def get_or_create_group_by_label(label, organization_id) do
    case Repo.get_by(Group, %{label: label}, organization_id: organization_id) do
      nil -> create_group(%{label: label, organization_id: organization_id})
      group -> {:ok, group}
    end
  end

  @doc """
  Fetches all group ids in an organization
  """
  @spec get_group_ids :: list()
  def get_group_ids do
    Group
    |> Repo.all()
    |> Enum.map(fn group -> group.id end)
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
    with {:ok, group} <-
           %Group{}
           |> Group.changeset(attrs)
           |> Repo.insert() do
      if Map.has_key?(attrs, :add_role_ids),
        do: update_group_roles(attrs, group),
        else: {:ok, group}
    end
  end

  @spec update_group_roles(map(), Group.t()) :: {:ok, Group.t()}
  defp update_group_roles(attrs, group) do
    %{access_controls: access_controls} =
      attrs
      |> Map.put(:group_id, group.id)
      |> GroupRole.update_group_roles()

    group
    |> Map.put(:roles, access_controls)
    |> then(&{:ok, &1})
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
      with {:ok, updated_group} <-
             group
             |> Group.changeset(attrs)
             |> Repo.update() do
        if Map.has_key?(attrs, :add_role_ids),
          do: update_group_roles(attrs, updated_group),
          else: {:ok, updated_group}
      end
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
    # check if an entry exists
    attrs = Map.take(attrs, [:contact_id, :group_id, :organization_id])

    case Repo.fetch_by(ContactGroup, attrs) do
      {:ok, cg} ->
        {:ok, cg}

      {:error, _} ->
        %ContactGroup{}
        |> ContactGroup.changeset(attrs)
        |> Repo.insert()
    end
  end

  @doc """
  Given a group id, get stats on the contacts within this group based on bsp_status
  and also the total count
  """
  @spec info_group_contacts(non_neg_integer) :: map()
  def info_group_contacts(group_id) do
    total =
      ContactGroup
      |> where([cg], cg.group_id == ^group_id)
      |> Repo.aggregate(:count)

    result = %{total: total}

    ContactGroup
    |> join(:inner, [cg], c in Contact, as: :c, on: cg.contact_id == c.id)
    |> where([cg], cg.group_id == ^group_id)
    |> where([c: c], c.status == :valid)
    |> group_by([c: c], c.bsp_status)
    |> select([c: c], [c.bsp_status, count(c.id)])
    |> Repo.all()
    |> Enum.reduce(
      result,
      fn [name, count], result -> Map.put(result, name, count) end
    )
  end

  @doc """
  This function will load id by label
  """
  @spec load_group_by_label(any) :: list
  def load_group_by_label(group_label) do
    group_label
    |> Enum.reduce([], fn label, acc ->
      case Repo.get_by(Group, %{label: label}) do
        nil -> "Sorry, some collections mentioned in the sheet doesn't exit."
        group -> [group | acc]
      end
    end)
  end

  @doc """
  Get the contacts ids for a specific group that have not opted out
  """
  @spec contact_ids(non_neg_integer) :: list(non_neg_integer)
  def contact_ids(group_id) do
    Contact
    |> where([c], c.status != :blocked and is_nil(c.optout_time))
    |> join(:inner, [c], cg in ContactGroup,
      as: :cg,
      on: cg.contact_id == c.id and cg.group_id == ^group_id
    )
    |> select([c], c.id)
    |> Repo.all()
  end

  @doc """
  Delete group contacts

  """
  @spec delete_group_contacts_by_ids(integer, list()) :: {integer(), nil | [term()]}
  def delete_group_contacts_by_ids(group_id, contact_ids) do
    fields = {{:group_id, group_id}, {:contact_id, contact_ids}}
    Repo.delete_relationships_by_ids(ContactGroup, fields)
  end

  @doc """
  Delete contact groups
  """
  @spec delete_contact_groups_by_ids(integer, list()) :: {integer(), nil | [term()]}
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

    group_ids = Enum.map(group_ids, fn group_id -> String.to_integer(group_id) end)
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
