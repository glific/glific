defmodule GlificWeb.Schema.ConsultingHourTypes do
  @moduledoc """
  GraphQL Representation of Glific's Consulting Hours DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo

  alias GlificWeb.{
    Resolvers,
    Schema.Middleware.Authorize
  }

  object :consulting_hour_result do
    field :consulting_hour, :consulting_hour
    field :errors, list_of(:input_error)
  end

  object :consulting_hour do
    field :participants, :string
    field :organization_name, :string
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
    field :organization_id, :id
    field :organization_name, :string
    field :staff, :string
    field :content, :string
    field :when, :datetime
    field :duration, :integer
    field :is_billable, :boolean
  end

  @desc "Filtering options for consulting hours"
  input_object :consulting_hour_filter do
    @desc "Match the organization name"
    field :organization_name, :string

    @desc "Match the participants name"
    field :participants, :string

    @desc "Match the staff name"
    field :staff, :string

    @desc "Match the billable flag"
    field :is_billable, :boolean
  end

  object :consulting_hours_queries do
    @desc "get the details of consulting hours"
    field :consulting_hour, :consulting_hour_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.ConsultingHours.get_consulting_hours/3)
    end

    @desc "Get a list of all consulting hours filtered by various criteria"
    field :consulting_hours, list_of(:consulting_hour) do
      arg(:filter, :consulting_hour_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.ConsultingHours.consulting_hours/3)
    end
  end

  object :consulting_hours_mutations do
    field :create_consulting_hour, :consulting_hour_result do
      arg(:input, non_null(:consulting_hour_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.ConsultingHours.create_consulting_hour/3)
    end

    field :update_consulting_hour, :consulting_hour_result do
      arg(:id, non_null(:id))
      arg(:input, :consulting_hour_input)
      middleware(Authorize, :staff)
      resolve(&Resolvers.ConsultingHours.update_consulting_hour/3)
    end

    field :delete_consulting_hour, :consulting_hour_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.ConsultingHours.delete_consulting_hour/3)
    end
  end
end
