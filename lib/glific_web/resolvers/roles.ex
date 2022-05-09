defmodule GlificWeb.Resolvers.Roles do
  @moduledoc """
  Roles Resolver which sits between the GraphQL schema and Glific role Context API.
  This layer basically stiches together one or more calls to resolve the incoming queries.
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
         do: {:ok, %{role: role}}
  end

  @doc """
  Get the list of roles
  """
  def roles(_, args, _) do
    # {:ok, AccessControl.list_roles(args)}
  end

  @doc false
  @spec create_role(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_role(_, %{input: params}, _) do
    with {:ok, role} <- AccessControl.create_role(params) do
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
