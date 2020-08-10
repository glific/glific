defmodule GlificWeb.Schema.ProviderTypes do
  @moduledoc """
  GraphQL Representation of Glific's Provider DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers

  object :provider_result do
    field :provider, :provider
    field :errors, list_of(:input_error)
  end

  object :provider do
    field :id, :id
    field :name, :string
    field :url, :string
    field :api_end_point, :string
  end

  @desc "Filtering options for providers"
  input_object :provider_filter do
    @desc "Match the name"
    field :name, :string

    @desc "Match the url of provider"
    field :url, :string
  end

  input_object :provider_input do
    field :name, :string
    field :url, :string
    field :api_end_point, :string
  end

  object :provider_queries do
    @desc "get the details of one provider"
    field :provider, :provider_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Partners.provider/3)
    end

    @desc "Get a list of all providers filtered by various criteria"
    field :providers, list_of(:provider) do
      arg(:filter, :provider_filter)
      arg(:opts, :opts)
      resolve(&Resolvers.Partners.providers/3)
    end

    @desc "Get a count of all providers filtered by various criteria"
    field :count_providers, :integer do
      arg(:filter, :provider_filter)
      resolve(&Resolvers.Partners.count_providers/3)
    end
  end

  object :provider_mutations do
    field :create_provider, :provider_result do
      arg(:input, non_null(:provider_input))
      resolve(&Resolvers.Partners.create_provider/3)
    end

    field :update_provider, :provider_result do
      arg(:id, non_null(:id))
      arg(:input, :provider_input)
      resolve(&Resolvers.Partners.update_provider/3)
    end

    field :delete_provider, :provider_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Partners.delete_provider/3)
    end
  end
end
