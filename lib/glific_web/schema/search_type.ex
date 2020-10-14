defmodule GlificWeb.Schema.SearchTypes do
  @moduledoc """
  GraphQL Representation of Glific's Search DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :saved_search_result do
    field :saved_search, :saved_search
    field :errors, list_of(:input_error)
  end

  object :saved_search do
    field :id, :id
    field :label, :string
    field :shortcode, :string
    field :args, :json

    # the number of contacts this saved search matches
    # this is an expensive operation
    field :count, :integer do
      resolve(fn saved_search, resolution, context ->
        Resolvers.Searches.saved_search_count(
          resolution,
          %{id: saved_search.id},
          context
        )
      end)
    end
  end

  object :conversation do
    field :contact, :contact
    field :messages, list_of(:message)
  end

  object :search_cup do
    field :contacts, list_of(:message)
    field :messages, list_of(:message)
    field :tags, list_of(:message)
  end

  input_object :saved_search_filter do
    field :label, :string
    field :shortcode, :string
  end

  input_object :saved_search_input do
    field :label, :string
    field :shortcode, :string
    field :args, :json
  end

  input_object :save_search_input do
    field :label, :string
    field :shortcode, :string
  end

  input_object :date_range_input do
    @desc "Start date for the filter"
    field :from, :date

    @desc "End date for the filter"
    field :to, :date
  end

  @desc "Filtering options for search"
  input_object :search_filter do
    @desc "Match one contact ID"
    field :id, :gid

    @desc "Match multiple contact ids"
    field :ids, list_of(:gid)

    @desc "Include conversations with these tags"
    field :include_tags, list_of(:gid)

    @desc "Include conversations with these groups"
    field :include_groups, list_of(:gid)

    @desc "Include conversations by these users"
    field :include_users, list_of(:gid)

    @desc "term for saving the search"
    field :term, :string

    @desc "term for saving the search"
    field :date_range, :date_range_input

    @desc "It will use the save search filters"
    field :saved_search_id, :id
  end

  object :search_queries do
    @desc "Search for conversations"
    field :search, list_of(:conversation) do
      arg(:save_search, :boolean, default_value: false)

      @desc "Inputs to save a search"
      arg(:save_search_input, :save_search_input)

      arg(:filter, non_null(:search_filter))
      arg(:message_opts, non_null(:opts))
      arg(:contact_opts, non_null(:opts))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Searches.search/3)
    end

    @desc "New Search for messages + contacts + tags"
    field :search_multi, :search_cup do
      arg(:filter, non_null(:search_filter))
      arg(:message_opts, non_null(:opts))
      arg(:contact_opts, non_null(:opts))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Searches.search_multi/3)
    end

    @desc "get the details of one saved search"
    field :saved_search, :saved_search_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Searches.saved_search/3)
    end

    @desc "Get a list of all searches"
    field :saved_searches, list_of(:saved_search) do
      arg(:filter, :saved_search_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Searches.saved_searches/3)
    end

    @desc "Get a count of all searches"
    field :count_saved_searches, :integer do
      arg(:filter, :saved_search_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Searches.count_saved_searches/3)
    end

    field :saved_search_count, :integer do
      # the id of the saved search
      arg(:id, non_null(:id))

      # if we want to add a search term
      arg(:term, :string)

      middleware(Authorize, :staff)
      resolve(&Resolvers.Searches.saved_search_count/3)
    end
  end

  object :search_mutations do
    field :create_saved_search, :saved_search_result do
      arg(:input, non_null(:saved_search_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Searches.create_saved_search/3)
    end

    field :update_saved_search, :saved_search_result do
      arg(:id, non_null(:id))
      arg(:input, :saved_search_input)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Searches.update_saved_search/3)
    end

    field :delete_saved_search, :saved_search_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Searches.delete_saved_search/3)
    end
  end
end
