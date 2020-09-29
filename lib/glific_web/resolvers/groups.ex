defmodule GlificWeb.Resolvers.Groups do
  @moduledoc """
  Group Resolver which sits between the GraphQL schema and Glific Group Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Groups, Groups.Group, Repo}
  alias Glific.{Groups.ContactGroup, Groups.UserGroup}
  alias GlificWeb.Resolvers.Helper

  @doc """
  Get a specific group by id
  """
  @spec group(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def group(_, %{id: id}, %{context: %{current_user: current_user}}) do
    with {:ok, group} <- Repo.fetch_by(Group, %{id: id, organization_id: current_user.organization_id}),
         do: {:ok, %{group: group}}
  end

  @doc """
  Get the list of groups filtered by args
  """
  @spec groups(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [Group]}
  def groups(_, args, context) do
    {:ok, Groups.list_groups(Helper.add_org_filter(args, context))}
  end

  @doc """
  Get the count of groups filtered by args
  """
  @spec count_groups(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_groups(_, args, context) do
    {:ok, Groups.count_groups(Helper.add_org_filter(args, context))}
  end

  @doc """
  Creates an group
  """
  @spec create_group(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_group(_, %{input: params}, _) do
    with {:ok, group} <- Groups.create_group(params) do
      {:ok, %{group: group}}
    end
  end

  @doc """
  Updates an group
  """
  @spec update_group(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_group(_, %{id: id, input: params}, %{context: %{current_user: current_user}}) do
    with {:ok, group} <- Repo.fetch_by(Group, %{id: id, organization_id: current_user.organization_id}),
         {:ok, group} <- Groups.update_group(group, params) do
      {:ok, %{group: group}}
    end
  end

  @doc """
  Deletes an group
  """
  @spec delete_group(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_group(_, %{id: id}, %{context: %{current_user: current_user}}) do
    with {:ok, group} <- Repo.fetch_by(Group, %{id: id, organization_id: current_user.organization_id}),
         {:ok, group} <- Groups.delete_group(group) do
      {:ok, group}
    end
  end

  @doc """
  Get count of group contacts
  """
  @spec contacts_count(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def contacts_count(_, params, _), do: {:ok, Groups.contacts_count(params)}

  @doc """
  Get count of group users
  """
  @spec users_count(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def users_count(_, params, _), do: {:ok, Groups.users_count(params)}

  @doc """
  Creates an contact group entry
  """
  @spec create_contact_group(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_contact_group(_, %{input: params}, _) do
    with {:ok, contact_group} <- Groups.create_contact_group(params) do
      {:ok, %{contact_group: contact_group}}
    end
  end

  @doc false
  @spec update_group_contacts(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_group_contacts(_, %{input: params}, _) do
    group_contacts = Groups.GroupContacts.update_group_contacts(params)
    {:ok, group_contacts}
  end

  @doc false
  @spec update_contact_groups(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_contact_groups(_, %{input: params}, _) do
    group_contacts = Groups.ContactGroups.update_contact_groups(params)
    {:ok, group_contacts}
  end

  @doc """
  Deletes an contact group entry
  """
  @spec delete_contact_group(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_contact_group(_, %{id: id}, _) do
    with {:ok, contact_group} <- Repo.fetch(ContactGroup, id),
         {:ok, contact_group} <- Groups.delete_contact_group(contact_group) do
      {:ok, contact_group}
    end
  end

  @doc """
  Creates an user group entry
  """
  @spec create_user_group(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_user_group(_, %{input: params}, _) do
    with {:ok, user_group} <- Groups.create_user_group(params) do
      {:ok, %{user_group: user_group}}
    end
  end

  @doc false
  @spec update_group_users(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_group_users(_, %{input: params}, _) do
    group_users = Groups.GroupUsers.update_group_users(params)
    {:ok, group_users}
  end

  @doc false
  @spec update_user_groups(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_user_groups(_, %{input: params}, _) do
    group_users = Groups.UserGroups.update_user_groups(params)
    {:ok, group_users}
  end

  @doc """
  Deletes an user group entry
  """
  @spec delete_user_group(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_user_group(_, %{id: id}, _) do
    with {:ok, user_group} <- Repo.fetch(UserGroup, id),
         {:ok, user_group} <- Groups.delete_user_group(user_group) do
      {:ok, user_group}
    end
  end
end
