defmodule GlificWeb.Schema.SearchTypes do
  @moduledoc """
  GraphQL Representation of Glific's Search DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers

  object :saved_search_result do
    field :saved_search, :saved_search
    field :errors, list_of(:input_error)
  end

  object :saved_search do
    field :id, :id
    field :label, :string
    field :args, :json
  end

  input_object :saved_search_input do
    field :label, :string
    field :args, :saved_search_args
  end

  @desc "args options for searches"
  input_object :saved_search_args do
    @desc "store search term"
    field :term, :string

    @desc "store include tags"
    field :include_tags, list_of(:gid)

    @desc "store exclude tags"
    field :exclude_tags, list_of(:gid)
  end

  object :search_queries do
    @desc "get the details of one saved search"
    field :saved_search, :saved_search_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Searches.saved_search/3)
    end

    @desc "Get a list of all searches"
    field :saved_searches, list_of(:saved_search) do
      resolve(&Resolvers.Searches.saved_searches/3)
    end
  end

  object :search_mutations do
    field :create_saved_search, :saved_search_result do
      arg(:input, non_null(:saved_search_input))
      resolve(&Resolvers.Searches.create_saved_search/3)
    end

    field :update_saved_search, :saved_search_result do
      arg(:id, non_null(:id))
      arg(:input, :saved_search_input)
      resolve(&Resolvers.Searches.update_saved_search/3)
    end

    field :delete_saved_search, :saved_search_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Searches.delete_saved_search/3)
    end
  end
end
