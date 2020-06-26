defmodule GlificWeb.Resolvers.Groups do
  @moduledoc """
  Group Resolver which sits between the GraphQL schema and Glific Group Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Repo, Groups, Groups.Group}
  alias Glific.{Groups.ContactGroup, Groups.UserGroup}

  @doc """
  Get a specific group by id
  """
  @spec group(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def group(_, %{id: id}, _) do
    with {:ok, group} <- Repo.fetch(Group, id),
         do: {:ok, %{group: group}}
  end

  @doc """
  Get the list of groups filtered by args
  """
  @spec groups(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [Group]}
  def groups(_, args, _) do
    {:ok, Groups.list_groups(args)}
  end

  @doc """
  Get the count of groups filtered by args
  """
  @spec count_groups(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_groups(_, args, _) do
    {:ok, Groups.count_groups(args)}
  end

  @doc false
  @spec create_group(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_group(_, %{input: params}, _) do
    with {:ok, group} <- Groups.create_group(params) do
      {:ok, %{group: group}}
    end
  end

  @doc false
  @spec update_group(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_group(_, %{id: id, input: params}, _) do
    with {:ok, group} <- Repo.fetch(Group, id),
         {:ok, group} <- Groups.update_group(group, params) do
      {:ok, %{group: group}}
    end
  end

  @doc false
  @spec delete_group(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_group(_, %{id: id}, _) do
    with {:ok, group} <- Repo.fetch(Group, id),
         {:ok, group} <- Groups.delete_group(group) do
      {:ok, group}
    end
  end
end
