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

  object :trigger_action do
    field :id, :id
    field :flow_id, :id
    field :group_id, :id
  end

  object :trigger_condition do
    field :id, :id
    field :start_at, :datetime
    field :ends_at, :datetime
    field :is_active, :boolean
    field :is_repeating, :boolean
    field :frequency, :string
  end

  object :trigger do
    field :id, :id
    field :name, :string
    field :event_type, :string

    field :trigger_action, :trigger_action do
      resolve(dataloader(Repo))
    end

    field :trigger_condition, :trigger_condition do
      resolve(dataloader(Repo))
    end
  end

  input_object :trigger_input do
    field :name, :string
    field :event_type, :string

    field :flow_id, :id
    field :group_id, :id

    field :is_repeating, :boolean
    field :frequency, :string
    field :start_at, :datetime
    field :ends_at, :datetime
  end

  object :trigger_mutations do
    field :create_trigger, :trigger_result do
      arg(:input, non_null(:trigger_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Triggers.create_trigger/3)
    end
  end
end
