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

    field :value, :string

    field :contact, :contact do
      resolve(dataloader(Repo))
    end
  end

  input_object :contact_wa_group_input do
    field :contact_id, :id
    field :wa_group_id, :id
  end

  input_object :wa_group_contacts_input do
    field :wa_group_id, non_null(:id)
    field :add_wa_contact_ids, non_null(list_of(:id))
    field :delete_wa_contact_ids, non_null(list_of(:id))
  end

  object :wa_group_contacts do
    field :number_deleted, :integer
    field :wa_group_contacts, list_of(:contact_wa_group)
  end

  object :contact_wa_groups do
    field :number_deleted, :integer
    field :contact_wa_groups, list_of(:contact_wa_group)
  end

  @desc "Filtering options for messages"
  input_object :contact_wa_group_filter do
    @desc "Match the contact id"
    field :contact_id, :id

    @desc "Match the group id"
    field :wa_group_id, :id

    @desc "Date range which will apply on date column. Default is inserted at."
    field :date_range, :date_range_input
  end

  object :contact_wa_group_queries do
    @desc "Get a list of all the contact associated with the contact"
    field :wa_groups_contact, list_of(:contact_wa_group) do
      arg(:filter, :contact_wa_group_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.wa_groups_contact/3)
    end
  end

  object :contact_wa_group_mutations do
    field :create_contact_wa_group, :contact_wa_group_result do
      arg(:input, non_null(:contact_wa_group_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.create_contact_wa_group/3)
    end

    field :update_wa_group_contacts, :wa_group_contacts do
      arg(:input, non_null(:wa_group_contacts_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.update_wa_group_contacts/3)
    end
  end
end
