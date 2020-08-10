defmodule Glific.Groups do
  @moduledoc """
  The Groups context.
  """
  import Ecto.Query, warn: false

  alias Glific.Repo

  alias Glific.Groups.{
    ContactGroup,
    Group,
    UserGroup
  }

  @doc """
  Returns the list of groups.

  ## Examples

      iex> list_groups()
      [%Group{}, ...]

  """
  @spec list_groups(map()) :: [Group.t()]
  def list_groups(args \\ %{}),
    do: Repo.list_filter(args, Group, &Repo.opts_with_label/2, &Repo.filter_with/2)

  @doc """
  Return the count of groups, using the same filter as list_groups
  """
  @spec count_groups(map()) :: integer
  def count_groups(args \\ %{}),
    do: Repo.count_filter(args, Group, &Repo.filter_with/2)

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
  def get_group!(id), do: Repo.get!(Group, id)

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
    group
    |> Group.changeset(attrs)
    |> Repo.update()
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
    Repo.delete(group)
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
  Deletes a contact group.

  ## Examples

      iex> delete_contact_group(contact_group)
      {:ok, %ContactGroup{}}

      iex> delete_contact_group(contact_group)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_contact_group(ContactGroup.t()) ::
          {:ok, ContactGroup.t()} | {:error, Ecto.Changeset.t()}
  def delete_contact_group(%ContactGroup{} = contact_group) do
    Repo.delete(contact_group)
  end

  @doc false
  @spec delete_contact_group_by_ids(integer, integer) :: {integer(), nil | [term()]}
  def delete_contact_group_by_ids(group_id, contact_id) when is_integer(contact_id) do
    fields = %{
      "key_1" => :group_id,
      "key_2" => :contact_id,
      "value_1" => group_id,
      "values_2" => [contact_id]
    }

    Repo.delete_relationships_by_ids(ContactGroup, fields)
  end

  @spec delete_contact_group_by_ids(integer, []) :: {integer(), nil | [term()]}
  def delete_contact_group_by_ids(group_id, contact_ids) when is_list(contact_ids) do
    fields = %{
      "key_1" => :group_id,
      "key_2" => :contact_id,
      "value_1" => group_id,
      "values_2" => contact_ids
    }

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
  Deletes a user group.

  ## Examples

      iex> delete_user_group(user_group)
      {:ok, %UserGroup{}}

      iex> delete_user_group(user_group)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_user_group(UserGroup.t()) :: {:ok, UserGroup.t()} | {:error, Ecto.Changeset.t()}
  def delete_user_group(%UserGroup{} = user_group) do
    Repo.delete(user_group)
  end

  @doc """
  In Join tables we rarely use the table id. We always know the object ids
  and hence more convenient to delete an entry via its object ids.
  We will generalize this function and move it to Repo.ex when we get a better
  handle on how to do so :)
  """
  @spec delete_user_group_by_ids(integer, integer) :: {integer(), nil | [term()]}
  def delete_user_group_by_ids(group_id, user_id) when is_integer(user_id) do
    %UserGroup{}
    |> where([m], m.group_id == ^group_id and m.user_id == ^user_id)
    |> Repo.delete_all()
  end

  @spec delete_user_group_by_ids(integer, []) :: {integer(), nil | [term()]}
  def delete_user_group_by_ids(group_id, user_ids) when is_list(user_ids) do
    UserGroup
    |> where([m], m.group_id == ^group_id and m.user_id in ^user_ids)
    |> Repo.delete_all()
  end

  @doc """
  Updates user groups entries
  """
  @spec update_user_groups(map()) :: :ok
  def update_user_groups(%{user_id: user_id, group_ids: group_ids}) do
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
        %{user_id: user_id, group_id: group_id}
      end)

    UserGroup
    |> Repo.insert_all(new_group_entries)

    UserGroup
    |> where([ug], ug.user_id == ^user_id and ug.group_id in ^delete_group_ids)
    |> Repo.delete_all()

    :ok
  end
end
