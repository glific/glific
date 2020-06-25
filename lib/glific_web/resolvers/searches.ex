defmodule GlificWeb.Resolvers.Searches do
  @moduledoc """
  Search Resolver which sits between the GraphQL schema and Glific search Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Repo, Searches, Searches.Search}

  @doc """
  Get a specific search by id
  """
  @spec search(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, map()} | {:error, any}
  def search(_, %{id: id}, _) do
    with {:ok, search} <- Repo.fetch(Search, id),
         do: {:ok, %{search: search}}
  end

  @doc """
  Get the list of searches
  """
  @spec searches(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [Search]}
  def searches(_, args, _) do
    {:ok, Searches.list_searches(args)}
  end

  @doc false
  @spec create_search(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_search(_, %{input: params}, _) do
    with {:ok, search} <- Searches.create_search(params) do
      {:ok, %{search: search}}
    end
  end

  @doc false
  @spec update_search(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_search(_, %{id: id, input: params}, _) do
    with {:ok, search} <- Repo.fetch(Search, id),
         {:ok, search} <- Searches.update_search(search, params) do
      {:ok, %{search: search}}
    end
  end

  @doc false
  @spec delete_search(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_search(_, %{id: id}, _) do
    with {:ok, search} <- Repo.fetch(Search, id),
         {:ok, search} <- Searches.delete_search(search) do
      {:ok, search}
    end
  end
end
