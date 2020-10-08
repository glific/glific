defmodule GlificWeb.Resolvers.Searches do
  @moduledoc """
  Searches Resolver which sits between the GraphQL schema and Glific saved_search Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    Conversations.Conversation,
    Repo,
    Searches,
    Searches.SavedSearch,
    Searches.Search,
  }

  alias GlificWeb.Resolvers.Helper

  @doc """
  Get a specific saved_search by id
  """
  @spec saved_search(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, map()} | {:error, any}
  def saved_search(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, saved_search} <-
           Repo.fetch_by(SavedSearch, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{saved_search: saved_search}}
  end

  @doc """
  Get the list of saved_searches
  """
  @spec saved_searches(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [SavedSearch]}
  def saved_searches(_, args, context) do
    {:ok, Searches.list_saved_searches(Helper.add_org_filter(args, context))}
  end

  @doc """
  Get the count of saved_searches
  """
  @spec count_saved_searches(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_saved_searches(_, args, context) do
    {:ok, Searches.count_saved_searches(Helper.add_org_filter(args, context))}
  end

  @doc false
  @spec create_saved_search(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_saved_search(_, %{input: params}, _) do
    with {:ok, saved_search} <- Searches.create_saved_search(params) do
      {:ok, %{saved_search: saved_search}}
    end
  end

  @doc false
  @spec update_saved_search(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_saved_search(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, saved_search} <-
           Repo.fetch_by(SavedSearch, %{id: id, organization_id: user.organization_id}),
         {:ok, saved_search} <- Searches.update_saved_search(saved_search, params) do
      {:ok, %{saved_search: saved_search}}
    end
  end

  @doc false
  @spec delete_saved_search(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_saved_search(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, saved_search} <-
           Repo.fetch_by(SavedSearch, %{id: id, organization_id: user.organization_id}),
         {:ok, saved_search} <- Searches.delete_saved_search(saved_search) do
      {:ok, saved_search}
    end
  end

  @doc false
  @spec search(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [any]}
  def search(_, params, context) do
    {:ok, Searches.search(Helper.add_org_filter(params, context))}
  end

  @doc false
  @spec search_multi(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, Search.t()}
  def search_multi(_, params, context) do
    {:ok,
     Searches.search_multi(
       params.filter[:term],
       Helper.add_org_filter(params, context)
     )}
  end

  @doc false
  @spec saved_search_count(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [Conversation.t()] | integer}
  def saved_search_count(_, params, context),
    do: {:ok, Searches.saved_search_count(Helper.add_org_filter(params, context))}
end
