defmodule GlificWeb.Schema.ContactWaGroupTypes do
  @moduledoc """
  GraphQL Representation of Glific's Contact Group DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :contact_wa_group_result do
    field :contact_wa_group, :contact_wa_group
    field :errors, list_of(:input_error)
  end

  object :contact_wa_group do
    field :id, :id

    field :contact, :contact do
      resolve(dataloader(Repo))
    end
  end

  object :sync_wa_contacts do
    field :message, :string
    field :errors, list_of(:input_error)
  end

  input_object :contact_wa_group_input do
    field :contact_id, :id
    field :wa_group_id, :id
    field :is_admin, :boolean
  end

  input_object :update_contact_wa_groups_input do
    field :wa_group_id, non_null(:id)
    field :add_wa_contact_ids, non_null(list_of(:id))
    field :delete_wa_contact_ids, non_null(list_of(:id))
  end

  object :update_contact_wa_groups_result do
    field :number_deleted, :integer
    field :wa_group_contacts, list_of(:contact_wa_group)
  end

  @desc "Filtering options for messages"
  input_object :contact_wa_group_filter do
    @desc "Match the group id"
    field :wa_group_id, :id

    @desc "Date range which will apply on date column. Default is inserted at."
    field :date_range, :date_range_input
  end

  object :contact_wa_group_queries do
    @desc "Get a list of all the contacts associated with the wa group"
    field :list_contact_wa_group, list_of(:contact_wa_group) do
      arg(:filter, :contact_wa_group_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.list_contact_wa_group/3)
    end
  end

  object :contact_wa_group_mutations do
    field :create_contact_wa_group, :contact_wa_group_result do
      arg(:input, non_null(:contact_wa_group_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.create_contact_wa_group/3)
    end

    field :update_contact_wa_groups, :update_contact_wa_groups_result do
      arg(:input, non_null(:update_contact_wa_groups_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.update_contact_wa_groups/3)
    end

    field :sync_contact_wa_groups, :sync_wa_contacts do
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.sync_contact_wa_groups/3)
    end
  end
end
