defmodule GlificWeb.Schema.ContactGroupTypes do
  @moduledoc """
  GraphQL Representation of Glific's Contact Group DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers

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

  object :contact_group_mutations do
    field :create_contact_group, :contact_group_result do
      arg(:input, non_null(:contact_group_input))
      resolve(&Resolvers.Groups.create_contact_group/3)
    end

    field :delete_contact_group, :contact_group_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Groups.delete_contact_group/3)
    end
  end
end
