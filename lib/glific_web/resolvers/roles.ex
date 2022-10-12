defmodule GlificWeb.Resolvers.Roles do
  @moduledoc """
  Roles Resolver which sits between the GraphQL schema and Glific role Context API.
  This layer basically stitches together one or more calls to resolve the incoming queries.
  """

  # import GlificWeb.Gettext

  alias Glific.{
    AccessControl,
    AccessControl.Role,
    Repo
  }

  @doc """
  Get a specific role by id
  """
  @spec role(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def role(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, role} <- Repo.fetch_by(Role, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{access_role: role}}
  end

  @doc """
  Get the list of roles filtered by args
  """
  @spec roles(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [Role.t()]}
  def roles(_, args, _) do
    {:ok, AccessControl.list_roles(args)}
  end

  @doc """
  Get the list of roles filtered by args
  """
  @spec count_roles(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_roles(_, args, _) do
    {:ok, AccessControl.count_roles(args)}
  end

  @doc false
  @spec create_role(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, Role.t()} | {:error, any}
  def create_role(_, %{input: params}, _) do
    with {:ok, role} <- AccessControl.create_role(params) do
      {:ok, %{access_role: role}}
    end
  end

  @doc """
  Updates the role
  """

  @spec update_role(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_role(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, role} <- Repo.fetch_by(Role, %{id: id, organization_id: user.organization_id}),
         {:ok, role} <- AccessControl.update_role(role, params) do
      {:ok, %{access_role: role}}
    end
  end

  @doc false
  @spec delete_role(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_role(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, role} <- Repo.fetch_by(Role, %{id: id, organization_id: user.organization_id}) do
      AccessControl.delete_role(role)
    end
  end
end
