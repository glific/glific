defmodule GlificWeb.Schema.WAManagedPhoneTypes do
  @moduledoc """
  GraphQL Representation of Glific's WAManagedPhone DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :wa_managed_phone_result do
    field :wa_managed_phone, :wa_managed_phone
    field :errors, list_of(:input_error)
  end

  object :wa_managed_phone do
    field :id, :id
    field :phone, :string
    field :phone_id, :integer
    field :label, :string
    field :status, :string
    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :contact, :contact do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :organization, :organization do
      resolve(dataloader(Repo))
    end
  end

  @desc "Filtering options for wa_managed_phones"
  input_object :wa_managed_phone_filter do
    @desc "Match the label"
    field :label, :string

    @desc "Match the phone"
    field :phone, :string
  end

  object :wa_managed_phone_queries do
    @desc "Get a list of all wa_managed_phones filtered by various criteria"
    field :wa_managed_phones, list_of(:wa_managed_phone) do
      arg(:filter, :wa_managed_phone_filter)
      arg(:opts, :opts)
      middleware(Authorize, :manager)
      resolve(&Resolvers.WAManagedPhones.wa_managed_phones/3)
    end

    @desc "Get a count of all wa_managed_phones filtered by various criteria"
    field :count_wa_managed_phones, :integer do
      arg(:filter, :wa_managed_phone_filter)
      middleware(Authorize, :manager)
      resolve(&Resolvers.WAManagedPhones.count_wa_managed_phones/3)
    end
  end
end
