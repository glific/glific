defmodule GlificWeb.Schema.ExtensionTypes do
  @moduledoc """
  GraphQL Representation of Glific's Extension DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo

  alias GlificWeb.{
    Resolvers,
    Schema.Middleware.Authorize
  }

  object :extension_result do
    field :extension, :extension
    field :errors, list_of(:input_error)
  end

  object :extension do
    field :id, :id
    field :name, :string
    field :code, :string
    field :module, :string
    field :is_valid, :boolean
    field :is_active, :boolean

    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :organization, :organization do
      resolve(dataloader(Repo))
    end
  end

  input_object :extension_input do
    field :code, non_null(:string)
    field :is_active, :boolean
    field :name, :string
    field :client_id, non_null(:id)
  end

  object :extensions_queries do
    @desc "get the details of one extension"
    field :extension, :extension_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Extensions.extension/3)
    end
  end

  object :extensions_mutations do
    field :create_extension, :extension_result do
      arg(:input, non_null(:extension_input))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Extensions.create_extension/3)
    end

    field :update_extension, :extension_result do
      arg(:id, non_null(:id))
      arg(:input, :extension_input)
      middleware(Authorize, :admin)
      resolve(&Resolvers.Extensions.update_extension/3)
    end

    field :delete_extension, :extension_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Extensions.delete_extension/3)
    end
  end
end
