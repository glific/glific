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
    field :id, :id
    field :label, :string
    field :bsp_id, :string

    field :last_communication_at, :datetime

    field :wa_managed_phone, :wa_managed_phone do
      resolve(dataloader(Repo))
    end
  end

  @desc "Filtering options for messages"
  input_object :wa_group_filter do
    @desc "Match the group id"
    field :group_id, :id
  end

  object :wa_group_queries do
    @desc "Get a list of all messages filtered by various criteria"
    field :wa_groups, list_of(:wa_group_result) do
      arg(:filter, :wa_group_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WaGroup.wa_groups/3)
    end
  end
end
