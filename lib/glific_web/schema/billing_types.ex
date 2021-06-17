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

  object :coupon_code_result do
    field :id, :string
    field :code, :string
    field :metadata, :json
  end

  object :subscription_result do
    field :subscription, :json
    field :errors, :string
  end

  object :customer_portal_result do
    field :url, :string
    field :return_url, :string
  end

  object :billing do
    field :id, :id
    field :name, :string
    field :email, :string
    field :currency, :string
    field :is_active, :boolean
    field :stripe_customer_id, :string
    field :stripe_payment_method_id, :string
    field :stripe_subscription_id, :string
    field :stripe_subscription_items, :json
    field :stripe_subscription_status, :string
    field :stripe_last_usage_recorded, :datetime
    field :stripe_current_period_start, :datetime
    field :stripe_current_period_end, :datetime
  end

  input_object :billing_input do
    field :organization_id, :gid
    field :name, :string
    field :email, :string
    field :currency, :string
    field :stripe_subscription_status, :string
    field :stripe_subscription_id, :string
  end

  object :billing_queries do
    @desc "get the details of one billing"
    field :billing, :billing_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Billings.billing/3)
    end

    @desc "get customer portal link"
    field :customer_portal, :customer_portal_result do
      middleware(Authorize, :admin)
      resolve(&Resolvers.Billings.customer_portal/3)
    end

    @desc "get the details of active billing of organization"
    field :get_organization_billing, :billing_result do
      arg(:organization_id, :gid)
      middleware(Authorize, :admin)
      resolve(&Resolvers.Billings.get_organization_billing/3)
    end

    @desc "get the details of promotion codes"
    field :get_coupon_code, :coupon_code_result do
      arg(:code, non_null(:string))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Billings.get_promo_code/3)
    end
  end

  object :billing_mutations do
    field :create_billing, :billing_result do
      arg(:input, non_null(:billing_input))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Billings.create_billing/3)
    end

    field :create_billing_subscription, :subscription_result do
      arg(:stripe_payment_method_id, non_null(:string))
      arg(:coupon_code, :string)
      middleware(Authorize, :admin)
      resolve(&Resolvers.Billings.create_subscription/3)
    end

    field :update_payment_method, :billing_result do
      arg(:stripe_payment_method_id, non_null(:string))
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
