defmodule GlificWeb.Resolvers.Searches do
  @moduledoc """
  Searches Resolver which sits between the GraphQL schema and Glific saved_search Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Repo, Searches, Searches.SavedSearch}

  @doc """
  Get a specific saved_search by id
  """
  @spec saved_search(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, map()} | {:error, any}
  def saved_search(_, %{id: id}, _) do
    with {:ok, saved_search} <- Repo.fetch(SavedSearch, id),
         do: {:ok, %{saved_search: saved_search}}
  end

  @doc """
  Get the list of saved_searches
  """
  @spec saved_searches(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [SavedSearch]}
  def saved_searches(_, args, _) do
    {:ok, Searches.list_saved_searches(args)}
  end

  @doc false
  @spec create_saved_search(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_saved_search(_, params, _) do
    with {:ok, saved_search} <- Searches.create_saved_search(params) do
      {:ok, %{saved_search: saved_search}}
    end
  end

  @doc false
  @spec update_saved_search(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_saved_search(_, %{id: id, input: params}, _) do
    with {:ok, saved_search} <- Repo.fetch(SavedSearch, id),
         {:ok, saved_search} <- Searches.update_saved_search(saved_search, params) do
      {:ok, %{saved_search: saved_search}}
    end
  end

  @doc false
  @spec delete_saved_search(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_saved_search(_, %{id: id}, _) do
    with {:ok, saved_search} <- Repo.fetch(SavedSearch, id),
         {:ok, saved_search} <- Searches.delete_saved_search(saved_search) do
      {:ok, saved_search}
    end
  end

  @doc false
  @spec search(Absinthe.Resolution.t(), %{term: String.t()}, %{context: map()}) ::
          {:ok, [any]}
  def search(_, params, _), do: {:ok, Searches.search(params)}

end
