defmodule GlificWeb.Resolvers.AccessControl do
  @moduledoc """
  AccessControl Resolver which sits between the GraphQL schema and Glific access control Context API.
  This layer basically stiches together one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    AccessControl,
    Repo
  }

  @doc """
  Updates the control accesses
  """
  @spec update_control_access(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_control_access(_, %{input: params}, _) do
    access_control = AccessControl.update_control_access(params)
    {:ok, access_control}
  end
end
