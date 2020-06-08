defmodule GlificWeb.Schema.ContactTagTypes do
  @moduledoc """
  GraphQL Representation of Glific's Contact Tag DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers

  object :contact_tag_result do
    field :contact_tag, :contact_tag
    field :errors, list_of(:input_error)
  end

  object :contact_tag do
    field :id, :id

    field :contact, :contact do
      resolve(dataloader(Repo))
    end

    field :tag, :tag do
      resolve(dataloader(Repo))
    end
  end

  input_object :contact_tag_input do
    field :contact_id, :id
    field :tag_id, :id
  end

  object :contact_tag_queries do
    field :contact_tag, :contact_tag_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Tags.contact_tag/3)
    end
  end

  object :contact_tag_mutations do
    field :create_contact_tag, :contact_tag_result do
      arg(:input, non_null(:contact_tag_input))
      resolve(&Resolvers.Tags.create_contact_tag/3)
    end

    field :delete_contact_tag, :contact_tag_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Tags.delete_contact_tag/3)
    end
  end
end
