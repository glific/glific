defmodule GlificWeb.Schema.TriggerTypes do
  @moduledoc """
  GraphQL Representation of Glific's Trigger DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :trigger_result do
    field :trigger, :trigger
    field :errors, list_of(:input_error)
  end

  object :trigger do
    field :id, :id
    field :name, :string
    field :trigger_type, :string

    field :start_at, :datetime
    field :end_at, :datetime
    field :is_active, :boolean
    field :is_repeating, :boolean
    field :frequency, list_of(:string)

    field :flow, :flow do
      resolve(dataloader(Repo))
    end

    field :contact, :contact do
      resolve(dataloader(Repo))
    end

    field :group, :group do
      resolve(dataloader(Repo))
    end
  end

  @desc "Filtering options for triggers"
  input_object :trigger_filter do
    @desc "Match the name"
    field :name, :string
  end

  input_object :trigger_input do
    field :name, :string
    field :trigger_type, :string

    field :flow_id, :id
    field :contact_id, :id
    field :group_id, :id

    field :is_active, :boolean
    field :is_repeating, :boolean
    field :frequency, list_of(:string)
    field :start_at, :datetime
    field :end_at, :datetime
  end

  input_object :trigger_update_input do
    field :flow_id, :id
    field :contact_id, :id
    field :group_id, :id

    field :is_active, :boolean
    field :is_repeating, :boolean
    field :frequency, list_of(:string)
    field :start_at, :datetime
    field :end_at, :datetime
  end

  object :trigger_queries do
    field :trigger, :trigger_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Triggers.trigger/3)
    end

    field :triggers, list_of(:trigger) do
      arg(:filter, :trigger_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Triggers.triggers/3)
    end

    field :count_triggers, :integer do
      arg(:filter, :trigger_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Triggers.count_triggers/3)
    end
  end

  object :trigger_mutations do
    field :create_trigger, :trigger_result do
      arg(:input, non_null(:trigger_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Triggers.create_trigger/3)
    end

    field :update_trigger, :trigger_result do
      arg(:id, non_null(:id))
      arg(:input, non_null(:trigger_update_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Triggers.update_trigger/3)
    end
  end
end
