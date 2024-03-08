defmodule GlificWeb.Resolvers.WACollection do
  @moduledoc """
  Group Resolver which sits between the GraphQL schema and Glific Group Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    Groups.WaGroupsCollections
  }

  @doc """
  Creates an whatsapp groups collection entry
  """
  @spec create_wa_groups_collection(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_wa_groups_collection(_, %{input: params}, _) do
    with {:ok, wa_groups_collection} <- WaGroupsCollections.create_wa_groups_collection(params) do
      {:ok, %{wa_groups_collection: wa_groups_collection}}
    end
  end

  @doc false
  @spec update_collection_wa_group(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_collection_wa_group(_, %{input: params}, _) do
    wa_groups_collection = WaGroupsCollections.update_collection_wa_group(params)
    {:ok, wa_groups_collection}
  end

  @doc false
  @spec update_wa_group_collection(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_wa_group_collection(_, %{input: params}, _) do
    wa_groups_collection = WaGroupsCollections.update_wa_group_collection(params)
    {:ok, wa_groups_collection}
  end

  @doc """
  Get the count of groups filtered by args
  """
  @spec count_wa_groups_collection(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def count_wa_groups_collection(_, args, _) do
    {:ok, WaGroupsCollections.count_wa_groups_collection(args)}
  end
end
