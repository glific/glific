defmodule GlificWeb.Schema.WAGroupsCollectionTypes do
  @moduledoc """
  GraphQL Representation of Glific's whatsapp Groups collection DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :wa_groups_collection_result do
    field :wa_groups_collection, :wa_groups_collection
    field :errors, list_of(:input_error)
  end

  object :wa_groups_collection do
    field :id, :id

    field :group, :group do
      resolve(dataloader(Repo))
    end
  end

  input_object :wa_groups_collection_input do
    field :group_id, :id
    field :wa_group_id, :id
  end

  input_object :update_collection_wa_group_input do
    field :group_id, non_null(:id)
    field :add_wa_group_ids, non_null(list_of(:id))
    field :delete_wa_group_ids, non_null(list_of(:id))
  end

  object :collection_wa_group_result do
    field :wa_groups_deleted, :integer
    field :collection_wa_groups, list_of(:wa_groups_collection)
  end

  input_object :update_wa_groups_collection_input do
    field :wa_group_id, non_null(:id)
    field :add_group_ids, non_null(list_of(:id))
    field :delete_group_ids, non_null(list_of(:id))
  end

  @desc "Filtering options for messages"
  input_object :wa_groups_collection_filter do
    @desc "Match the group id"
    field :group_id, :id

    @desc "Date range which will apply on date column. Default is inserted at."
    field :date_range, :date_range_input
  end

  object :wa_groups_collection_queries do
    @desc "Get a list of all the contacts associated with the wa group"
    field :list_wa_groups_collection, list_of(:wa_groups_collection) do
      arg(:filter, :wa_groups_collection_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WACollection.list_wa_groups_collection/3)
    end

    @desc "Get a count of all the wa groups associated with the group"
    field :count_wa_groups_collection, :integer do
      arg(:filter, :wa_groups_collection_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WACollection.count_wa_groups_collection/3)
    end
  end

  object :wa_groups_collection_mutations do
    field :create_wa_groups_collection, :wa_groups_collection_result do
      arg(:input, non_null(:wa_groups_collection_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.WACollection.create_wa_groups_collection/3)
    end

    field :update_collection_wa_group, :collection_wa_group_result do
      arg(:input, non_null(:update_collection_wa_group_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.WACollection.update_collection_wa_group/3)
    end

    field :update_wa_group_collection, :collection_wa_group_result do
      arg(:input, non_null(:update_wa_groups_collection_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.WACollection.update_wa_group_collection/3)
    end
  end
end
