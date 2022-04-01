defmodule GlificWeb.Schema.FlowLabelTypes do
  @moduledoc """
  GraphQL Representation of FlowLabel DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :flow_label_result do
    field :flow_label, :flow_label
    field :errors, list_of(:input_error)
  end

  object :flow_label do
    field :id, :id
    field :uuid, :uuid4
    field :name, :string
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  input_object :flow_label_input do
    field :name, :string
  end

  @desc "Filtering options for flow labels"
  input_object :flow_label_filter do
    @desc "Match the name"
    field :name, :string
  end

  object :flow_label_queries do
    @desc "get the details of one flow label"
    field :flow_label, :flow_label_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.FlowLabels.flow_label/3)
    end

    @desc "Get a list of all flow labels"
    field :flow_labels, list_of(:flow_label) do
      arg(:filter, :flow_label_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.FlowLabels.flow_labels/3)
    end

    @desc "Get a count of all flow labels filtered by various criteria"
    field :count_flow_labels, :integer do
      arg(:filter, :flow_label_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.FlowLabels.count_flow_labels/3)
    end
  end
end
