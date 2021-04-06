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
    field :stripe_customer_id, :string
    field :stripe_payment_method_id, :string
    field :currency, :string
    field :stripe_current_period_start, :datetime
    field :stripe_current_period_end, :datetime
  end

  input_object :billing_input do
    field :name, :string
    field :email, :string
    field :currency, :string
  end

  input_object :payment_method_input do
    field :stripe_payment_method_id, :string
  end

  object :billing_queries do
    @desc "get the details of one billing"
    field :billing, :billing_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Billings.billing/3)
    end
  end

  object :billing_mutations do
    field :create_billing, :billing_result do
      arg(:input, non_null(:billing_input))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Billings.create_billing/3)
    end

    field :create_billing_subscription, :json do
      arg(:input, non_null(:payment_method_input))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Billings.create_subscription/3)
    end

    field :update_payment_method, :billing_result do
      arg(:input, non_null(:payment_method_input))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Billings.update_payment_method/3)
    end

    field :update_billing, :billing_result do
      arg(:id, non_null(:id))
      arg(:input, :billing_input)
      middleware(Authorize, :admin)
      resolve(&Resolvers.Billings.update_billing/3)
    end

    field :delete_billing, :billing_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Billings.delete_billing/3)
    end
  end
end
