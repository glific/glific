defmodule GlificWeb.Schema.ContactsFieldTypes do
  @moduledoc """
  GraphQL Representation of Glific's Contact Field DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.{
    Repo
  }

  alias GlificWeb.{
    Resolvers,
    Schema.Middleware.Authorize
  }

  object :contacts_field_result do
    field :contacts_field, :contacts_field
    field :errors, list_of(:input_error)
  end

  object :contacts_field do
    field :id, :id
    field :name, :string
    field :shortcode, :string
    field :value_type, :string
    field :scope, :string
    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :organization, :organization do
      resolve(dataloader(Repo))
    end
  end

  @desc "Filtering options for contacts field"
  input_object :contacts_field_filter do
    @desc "Match the name"
    field :name, :string

    @desc "Match the shortcode"
    field :shortcode, :string
  end

  input_object :contacts_field_input do
    field :name, :string
    field :shortcode, :string
    field :value_type, :string
    field :scope, :string
  end

  object :contacts_field_queries do
    @desc "get the details of one contacs field"
    field :contacts_field, :contacts_field_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.ContactsField.contacts_field/3)
    end
  end

  object :contacts_field_mutations do
    field :create_contacts_field, :contacts_field_result do
      arg(:input, non_null(:contacts_field_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.ContactsField.create_contacts_field/3)
    end

    field :update_contacts_field, :contacts_field_result do
      arg(:id, non_null(:id))
      arg(:input, :contacts_field_input)
      middleware(Authorize, :staff)
      resolve(&Resolvers.ContactsField.update_contacts_field/3)
    end

    field :delete_contacts_field, :contacts_field_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.ContactsField.delete_contacts_field/3)
    end
  end
end
