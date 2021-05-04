defmodule GlificWeb.Schema.MessageTypes do
  @moduledoc """
  GraphQL Representation of Glific's Consulting Hours DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 2]

  alias Glific.Repo

  alias GlificWeb.{
    Resolvers,
    Schema,
    Schema.Middleware.Authorize
  }

  object :consulting_hour_result do
    field :consulting_hour, :consulting_hour
    field :errors, list_of(:input_error)
  end

  object :consulting_hour do
    field :participants, :string
    field :staff, :string
    field :content, :string
    field :when, :datetime
    field :duration, :integer
    field :is_billable, :boolean

    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :organization, :organization do
      resolve(dataloader(Repo))
    end
  end

  input_object :consulting_hour_input do
    field :participants, :string
    field :staff, :string
    field :content, :string
    field :when, :datetime
    field :duration, :integer
    field :is_billable, :boolean
  end

  object :consulting_hours_queries do
    @desc "get the details of consulting hours"
    field :consulting_hour, :consulting_hour_result do
      arg(:input, non_null(:consulting_hour_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.ConsultingHours.get_consulting_hours/3)
    end
  end

  object :consulting_hours_mutations do
    field :create_consulting_hour, :consulting_hour_result do
      arg(:input, non_null(:consulting_hour_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.ConsultingHours.create_consulting_hour/3)
    end
  end
end
