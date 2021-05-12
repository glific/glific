defmodule GlificWeb.Schema.ContactFieldTypes do
  @moduledoc """
  GraphQL Representation of Glific's Contact Field DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.{
    Contacts.ContactsField,
    Repo
  }

  alias GlificWeb.{
    Resolvers,
    Schema.Middleware.Authorize
  }

  object :contact_field_result do
    field :contact_field, :contact_field
    field :errors, list_of(:input_error)
  end

  object :contact_field do
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
end
