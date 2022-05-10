defmodule GlificWeb.Resolvers.AccessControl do
  @moduledoc """
  AccessControl Resolver which sits between the GraphQL schema and Glific access control Context API.
  This layer basically stiches together one or more calls to resolve the incoming queries.
  """

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
  Updates the control accesses
  """
  @spec update_control_access(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_control_access(_, %{input: params}, _) do
    access_control = AccessControls.update_control_access(params)
    {:ok, access_control}
  end
end
