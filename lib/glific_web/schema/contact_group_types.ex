defmodule GlificWeb.Schema.ContactGroupTypes do
  @moduledoc """
  GraphQL Representation of Glific's Contact Group DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :contact_group_result do
    field :contact_group, :contact_group
    field :errors, list_of(:input_error)
  end

  object :contact_group do
    field :id, :id

    field :value, :string

    field :contact, :contact do
      resolve(dataloader(Repo))
    end

    field :group, :group do
      resolve(dataloader(Repo))
    end
  end

  input_object :contact_group_input do
    field :contact_id, :id
    field :group_id, :id
  end

  input_object :group_contacts_input do
    field :group_id, non_null(:id)
    field :add_contact_ids, non_null(list_of(:id))
    field :delete_contact_ids, non_null(list_of(:id))
  end

  object :group_contacts do
    field :number_deleted, :integer
    field :group_contacts, list_of(:contact_group)
  end

  input_object :contact_groups_input do
    field :contact_id, non_null(:id)
    field :add_group_ids, non_null(list_of(:id))
    field :delete_group_ids, non_null(list_of(:id))
  end

  object :contact_groups do
    field :number_deleted, :integer
    field :contact_groups, list_of(:contact_group)
  end

  object :contact_group_mutations do
    field :create_contact_group, :contact_group_result do
      arg(:input, non_null(:contact_group_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Groups.create_contact_group/3)
    end

    field :update_group_contacts, :group_contacts do
      arg(:input, non_null(:group_contacts_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Groups.update_group_contacts/3)
    end

    field :update_contact_groups, :contact_groups do
      arg(:input, non_null(:contact_groups_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Groups.update_contact_groups/3)
    end
  end
end
