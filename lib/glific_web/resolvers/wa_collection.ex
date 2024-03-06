defmodule GlificWeb.Resolvers.WACollection do
  @moduledoc """
  Group Resolver which sits between the GraphQL schema and Glific Group Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    Groups.WaGroupsCollections
  }

  @doc """
  Get the list of whastapp groups filtered by args
  """
  @spec list_wa_groups_colection(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def list_wa_groups_colection(_, args, _) do
    {:ok, WaGroupsCollections.list_wa_groups_colection(args)}
  end

  @doc """
  Creates an whatsapp groups collection entry
  """
  @spec create_wa_groups_collection(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_wa_groups_collection(_, %{input: params}, _) do
    IO.inspect(WaGroupsCollections.create_wa_groups_collection(params))
    with {:ok, wa_groups_collection} <- WaGroupsCollections.create_wa_groups_collection(params) do
      {:ok, %{wa_groups_collection: wa_groups_collection}}
    end
  end
end
