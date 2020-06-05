defmodule GlificWeb.Schema.OrganizationTypes do
  @moduledoc """
  GraphQL Representation of Glific's Organization DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers

  object :organization_result do
    field :organization, :organization
    field :errors, list_of(:input_error)
  end

  object :organization do
    field :id, :id
    field :name, :string
    field :display_name, :string
    field :bsp_key, :string
    field :contact_name, :string
    field :email, :string
    field :wa_number, :string

    field :bsp, :bsp do
      resolve(dataloader(Repo))
    end
  end

  @desc "Filtering options for organizations"
  input_object :organization_filter do
    field :name, :string

    field :display_name, :string
    field :email, :string

    field :contact_name, :string
    field :bsp_key, :string
    field :wa_number, :string
  end

  input_object :organization_input do
    field :name, :string
    field :display_name, :string
    field :contact_name, :string
    field :email, :string
    field :bsp_key, :string
    field :wa_number, :string

    field :bsp_id, :id
  end

  object :organization_queries do
    @desc "get the details of one organization"
    field :organization, :organization_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Partners.organization/3)
    end

    @desc "Get a list of all organizations filtered by various criteria"
    field :organizations, list_of(:organization) do
      arg(:filter, :organization_filter)
      arg(:order, type: :sort_order, default_value: :asc)
      resolve(&Resolvers.Partners.organizations/3)
    end
  end

  object :organization_mutations do
    field :create_organization, :organization_result do
      arg(:input, non_null(:organization_input))
      resolve(&Resolvers.Partners.create_organization/3)
    end

    field :update_organization, :organization_result do
      arg(:id, non_null(:id))
      arg(:input, :organization_input)
      resolve(&Resolvers.Partners.update_organization/3)
    end

    field :delete_organization, :organization_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Partners.delete_organization/3)
    end
  end
end
