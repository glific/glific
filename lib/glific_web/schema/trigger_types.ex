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

    field :start_at, :datetime
    field :end_date, :date
    field :is_active, :boolean

    field :is_repeating, :boolean
    field :frequency, :string
    field :days, list_of(:integer)
    field :hours, list_of(:integer)

    field :flow, :flow do
      resolve(dataloader(Repo))
    end

    field :group, :group do
      resolve(dataloader(Repo))
    end

    field :roles, list_of(:access_role) do
      resolve(dataloader(Repo))
    end
  end

  @desc "Filtering options for triggers"
  input_object :trigger_filter do
    @desc "Match the flow"
    field :flow, :string

    @desc "Match the name"
    field :name, :string

    @desc "Match the group"
    field :group, :string
  end

  input_object :trigger_input do
    field :flow_id, :id
    field :group_id, :id
    field :group_ids, list_of(:integer)

    field :is_active, :boolean
    field :is_repeating, :boolean
    field :frequency, list_of(:string)
    field :days, list_of(:integer)
    field :hours, list_of(:integer)

    # the input widgets in the front end collect this separately
    field :start_date, :date
    field :start_time, :time

    field :start_at, :datetime
    field :end_date, :date
    field :add_role_ids, list_of(:id)
    field :delete_role_ids, list_of(:id)
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
      arg(:input, non_null(:trigger_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Triggers.update_trigger/3)
    end

    field :delete_trigger, :trigger_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Triggers.delete_trigger/3)
    end
  end
end
