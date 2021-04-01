defmodule GlificWeb.Schema.BillingTypes do
  @moduledoc """
  GraphQL Representation of Glific's Billing DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :billing_result do
    field :billing, :billing
    field :errors, list_of(:input_error)
  end

  object :billing do
    field :id, :id
    field :name, :string
    field :email, :string
  end

  @desc "Filtering options for billings"
  input_object :billing_filter do
    @desc "Match the email"
    field :name, :string

    @desc "Match the email"
    field :email, :string
  end

  input_object :billing_input do
    field :name, :string
    field :email, :string
  end

  object :billing_queries do
    @desc "get the details of one billing"
    field :billing, :billing_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Billings.billing/3)
    end

  object :billing_mutations do
    field :create_billing, :billing_result do
      arg(:input, non_null(:billing_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Billings.create_billing/3)
    end

    field :update_billing, :billing_result do
      arg(:id, non_null(:id))
      arg(:input, :billing_input)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Billings.update_billing/3)
    end

    field :delete_billing, :billing_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Billings.delete_billing/3)
    end
  end
end
