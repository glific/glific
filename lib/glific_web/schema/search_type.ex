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
    field :is_reserved, :boolean
  end

  object :conversation do
    field :contact, :contact
    field :group, :group
    field :messages, list_of(:message)
  end

  object :search_cup do
    field :contacts, list_of(:contact)
    field :messages, list_of(:message)
    field :tags, list_of(:message)
    field :labels, list_of(:message)
  end

  object :wa_search_cup do
    field :wa_groups, list_of(:wa_group)
    field :wa_messages, list_of(:wa_message)
  end

  object :wa_conversation do
    field :group, :group
    field :wa_group, :wa_group
    field :wa_messages, list_of(:wa_message)
  end

  input_object :saved_search_filter do
    field :label, :string
    field :shortcode, :string
    field :is_reserved, :boolean
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

  input_object :date_expression_input do
    @desc "Start date for the filter"
    field :from_expression, :string

    @desc "End date for the filter"
    field :to_expression, :string
  end

  input_object :date_input do
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

    @desc "Should we return group conversations? If so we only examine include_groups"
    field :search_group, :boolean

    @desc "Include conversations with these tags"
    field :include_tags, list_of(:gid)

    @desc "Include conversations with these labels"
    field :include_labels, list_of(:gid)

    @desc "Include conversations with these groups"
    field :include_groups, list_of(:gid)

    @desc "Include conversations by these users"
    field :include_users, list_of(:gid)

    @desc "term for saving the search"
    field :term, :string

    @desc "status of the message, this replaces the unread/not responded tags"
    field :status, :string

    @desc "a static date range input field which will apply on updated at column."
    field :date_range, :date_input

    @desc "a dynamic date expression input field"
    field :date_expression, :date_expression_input

    @desc "It will use the save search filters"
    field :saved_search_id, :id

    @desc "Searches based on group label"
    field :group_label, :string
  end

  @desc "Filtering options for wa_search"
  input_object :wa_search_filter do
    @desc "Match one group ID"
    field :id, :gid

    @desc "Match multiple group ids"
    field :ids, list_of(:gid)

    @desc "Match one or multiple wa_managed_phone ids"
    field :wa_phone_ids, list_of(:gid)

    @desc "Match term for saving the search"
    field :term, :string

    @desc "match groups"
    field :search_group, :boolean

    @desc "Searches based on group label"
    field :group_label, :string
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

    @desc "Get a collection count for organization"
    field :collection_stats, :json do
      arg(:organization_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Searches.collection_stats/3)
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

  object :wa_search_queries do
    @desc "Search for whatsapp group conversations"
    field :wa_search, list_of(:wa_conversation) do
      arg(:wa_message_opts, non_null(:opts))
      arg(:wa_group_opts, non_null(:opts))
      arg(:filter, non_null(:wa_search_filter))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Searches.wa_search/3)
    end

    @desc "New Search for wa_messages + wa_groups"
    field :wa_search_multi, :wa_search_cup do
      arg(:filter, non_null(:wa_search_filter))
      arg(:wa_message_opts, non_null(:opts))
      arg(:wa_group_opts, non_null(:opts))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Searches.wa_search_multi/3)
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
