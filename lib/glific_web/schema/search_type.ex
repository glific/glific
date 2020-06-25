defmodule GlificWeb.Schema.SearchTypes do
  @moduledoc """
  GraphQL Representation of Glific's Search DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers

  object :search_result do
    field :search, :search
    field :errors, list_of(:input_error)
  end

  object :search do
    field :id, :id
    field :label, :string
    field :args, :string
  end

  input_object :search_input do
    field :label, :string
    field :args, :search_args
  end

  @desc "args options for searches"
  input_object :search_args do
    @desc "store search term"
    field :term, :string

    @desc "store include tags"
    field :include_tags, list_of(:gid)

    @desc "store exclude tags"
    field :exclude_tags, list_of(:gid)
  end

  object :search_queries do
    @desc "get the details of one search"
    field :search, :search_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Searches.search/3)
    end

    @desc "Get a list of all searches"
    field :searches, list_of(:search) do
      resolve(&Resolvers.Searches.searches/3)
    end
  end

  object :search_mutations do
    field :create_search, :search_result do
      arg(:input, non_null(:search_input))
      resolve(&Resolvers.Searches.create_search/3)
    end

    field :update_search, :search_result do
      arg(:id, non_null(:id))
      arg(:input, :search_input)
      resolve(&Resolvers.Searches.update_search/3)
    end

    field :delete_search, :search_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Searches.delete_search/3)
    end
  end
end
