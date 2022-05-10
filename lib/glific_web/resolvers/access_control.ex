defmodule GlificWeb.Resolvers.AccessControl do
  @moduledoc """
  AccessControl Resolver which sits between the GraphQL schema and Glific access control Context API.
  This layer basically stiches together one or more calls to resolve the incoming queries.
  """

  # import GlificWeb.Gettext

  alias Glific.{
    AccessControl,
    AccessControls,
    Repo
  }

  @doc """
  Get a specific access_control by id
  """
  @spec access_control(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def access_control(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, access_control} <-
           Repo.fetch_by(AccessControl, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{access_control: access_control}}
  end

  @doc """
  Get the list of access controls filtered by args
  """
  @spec access_controls(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [AccessControl.t()]}
  def access_controls(_, args, _) do
    {:ok, AccessControls.list_access_controls(args)}
  end

  @doc """
  Get the count of access controls filtered by args
  """
  @spec count_access_controls(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_access_controls(_, args, _) do
    {:ok, AccessControls.count_access_controls(args)}
  end

  @doc """
  Creates the access_control
  """
  @spec create_access_control(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, AccessControl.t()} | {:error, any}
  def create_access_control(_, %{input: params}, _) do
    with {:ok, access_control} <- AccessControls.create_access_control(params) do
      {:ok, %{access_control: access_control}}
    end
  end

  @doc """
  Updates the access_control
  """
  @spec update_access_control(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_access_control(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, access_control} <-
           Repo.fetch_by(AccessControl, %{id: id, organization_id: user.organization_id}),
         {:ok, access_control} <- AccessControls.update_access_control(access_control, params) do
      {:ok, %{access_control: access_control}}
    end
  end

  @doc false
  @spec delete_access_control(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_access_control(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, access_control} <-
           Repo.fetch_by(AccessControl, %{id: id, organization_id: user.organization_id}),
         {:ok, access_control} <- AccessControls.delete_access_control(access_control) do
      {:ok, %{access_control: access_control}}
    end
  end
end
