defmodule GlificWeb.Schema.ProviderTypes do
  @moduledoc """
  GraphQL Representation of Glific's Provider DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :provider_result do
    field :provider, :provider
    field :errors, list_of(:input_error)
  end

  object :provider do
    field :id, :id
    field :name, :string
    field :shortcode, :string
    field :group, :string
    field :description, :string
    field :keys, :json
    field :secrets, :json
    field :is_required, :boolean

    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  @desc "Filtering options for providers"
  input_object :provider_filter do
    @desc "Match the name"
    field :name, :string

    @desc "Match the shortcode of provider"
    field :shortcode, :string
  end

  input_object :provider_input do
    field :name, :string
    field :shortcode, :string
    field :group, :string
    field :description, :string
    field :keys, :json
    field :secrets, :json
    field :is_required, :boolean
  end

  object :provider_queries do
    @desc "get the details of one provider"
    field :provider, :provider_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.provider/3)
    end

    @desc "getting bsp balance"
    field :bspbalance, :json do
      resolve(&Resolvers.Partners.bspbalance/3)
    end

    @desc "Get a list of all providers filtered by various criteria"
    field :providers, list_of(:provider) do
      arg(:filter, :provider_filter)
      arg(:opts, :opts)
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.providers/3)
    end

    @desc "Get a count of all providers filtered by various criteria"
    field :count_providers, :integer do
      arg(:filter, :provider_filter)
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.count_providers/3)
    end
  end

  object :provider_mutations do
    field :create_provider, :provider_result do
      arg(:input, non_null(:provider_input))
      middleware(Authorize, :glific_admin)
      resolve(&Resolvers.Partners.create_provider/3)
    end

    field :update_provider, :provider_result do
      arg(:id, non_null(:id))
      arg(:input, :provider_input)
      middleware(Authorize, :glific_admin)
      resolve(&Resolvers.Partners.update_provider/3)
    end

    field :delete_provider, :provider_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :glific_admin)
      resolve(&Resolvers.Partners.delete_provider/3)
    end
  end
end
