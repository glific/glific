defmodule GlificWeb.Schema.WaGroupTypes do
  @moduledoc """
  GraphQL Representation of Glific's whatsapp Groups DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :wa_group_result do
    field :wa_group, :wa_group
    field :errors, list_of(:input_error)
  end

  object :wa_group do
    field :id, :id
    field :label, :string
    field :bsp_id, :string

    field :last_communication_at, :datetime

    field :wa_managed_phone, :wa_managed_phone do
      resolve(dataloader(Repo))
    end

    field :fields, :json
  end

  @desc "Filtering options for wa groups"
  input_object :wa_group_filter do
    @desc "Include wa_groups within these groups"
    field :include_groups, list_of(:id)

    @desc "Exclude wa_groups within these groups"
    field :exclude_groups, list_of(:id)

    @desc "term for the search"
    field :term, :string

    @desc "Searches based on wa group label"
    field :label, :string
  end

  input_object :wa_group_input do
    field :fields, :json
  end

  object :wa_group_queries do
    @desc "get the details of one wa group"
    field :wa_group, :wa_group_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.wa_group/3)
    end

    @desc "Get a list of all wa groups filtered by various criteria"
    field :wa_groups, list_of(:wa_group) do
      arg(:filter, :wa_group_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.wa_groups/3)
    end

    field :wa_groups_count, :integer do
      arg(:filter, :wa_group_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.wa_groups_count/3)
    end
  end
end
