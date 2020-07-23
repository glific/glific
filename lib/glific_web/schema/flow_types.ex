defmodule GlificWeb.Schema.FlowTypes do
  @moduledoc """
  GraphQL Representation of Flow DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers

  object :flow_result do
    field :flow, :flow
    field :errors, list_of(:input_error)
  end

  object :flow do
    field :id, :id
    field :uuid, :uuid4
    field :name, :string
    field :shortcode, :string
    field :version_number, :string
    field :flow_type, :flow_type_enum

    field :language, :language do
      resolve(dataloader(Repo))
    end
  end

  input_object :flow_input do
    field :name, :string
    field :shortcode, :string
    field :language_id, :id
  end

  object :flow_queries do
    @desc "get the details of one flow"
    field :flow, :flow_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Flows.flow/3)
    end

    @desc "Get a list of all flows"
    field :flows, list_of(:flow) do
      resolve(&Resolvers.Flows.flows/3)
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
  end
end
