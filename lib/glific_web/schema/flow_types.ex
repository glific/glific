defmodule GlificWeb.Schema.FlowTypes do
  @moduledoc """
  GraphQL Representation of Flow DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers

  object :flow_result do
    field :flow, :flow
    field :errors, list_of(:input_error)
  end

  object :edit_flow_result do
    field :success, :boolean
    field :errors, list_of(:input_error)
  end

  object :flow do
    field :id, :id
    field :uuid, :uuid4
    field :name, :string
    field :shortcode, :string
    field :keywords, list_of(:string)
    field :ignore_keywords, :boolean
    field :version_number, :string
    field :flow_type, :flow_type_enum
  end

  input_object :flow_input do
    field :name, :string
    field :shortcode, :string
    field :keywords, list_of(:string)
    field :ignore_keywords, :boolean
  end

  @desc "Filtering options for flows"
  input_object :flow_filter do
    @desc "Match the name"
    field :name, :string
    @desc "Match the keyword"
    field :keyword, :string
  end

  object :flow_queries do
    @desc "get the details of one flow"
    field :flow, :flow_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Flows.flow/3)
    end

    @desc "Get a list of all flows"
    field :flows, list_of(:flow) do
      arg(:filter, :flow_filter)
      arg(:opts, :opts)
      resolve(&Resolvers.Flows.flows/3)
    end

    @desc "Get a count of all flows filtered by various criteria"
    field :count_flows, :integer do
      arg(:filter, :flow_filter)
      resolve(&Resolvers.Flows.count_flows/3)
    end
  end

  object :flow_mutations do
    field :create_flow, :flow_result do
      arg(:input, non_null(:flow_input))
      resolve(&Resolvers.Flows.create_flow/3)
    end

    field :update_flow, :flow_result do
      arg(:id, non_null(:id))
      arg(:input, :flow_input)
      resolve(&Resolvers.Flows.update_flow/3)
    end

    field :delete_flow, :flow_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Flows.delete_flow/3)
    end

    field :publish_flow, :edit_flow_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Flows.publish_flow/3)
    end
  end
end
