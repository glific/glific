defmodule GlificWeb.Schema.FlowTypes do
  @moduledoc """
  GraphQL Representation of Flow DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :flow_result do
    field :flow, :flow
    field :errors, list_of(:input_error)
  end

  object :common_flow_result do
    field :success, :boolean
    field :errors, list_of(:input_error)
  end

  object :export_flow do
    field :export_data, :json
  end

  object :flow do
    field :id, :id
    field :uuid, :uuid4
    field :name, :string
    field :keywords, list_of(:string)
    field :ignore_keywords, :boolean
    field :is_active, :boolean
    field :version_number, :string
    field :flow_type, :flow_type_enum
    field :inserted_at, :datetime
    field :updated_at, :datetime
    field :last_published_at, :datetime
    field :last_changed_at, :datetime
    field :is_background, :boolean
  end

  input_object :flow_input do
    field :name, :string
    field :keywords, list_of(:string)
    field :ignore_keywords, :boolean
    field :is_active, :boolean
    field :is_background, :boolean
  end

  @desc "Filtering options for flows"
  input_object :flow_filter do
    @desc "Match the name"
    field :name, :string

    @desc "Match the name and keyword"
    field :name_or_keyword, :string

    @desc "Match the keyword"
    field :keyword, :string

    @desc "Match the uuid"
    field :uuid, :uuid4

    @desc "Match the status of flow revision"
    field :status, :string

    @desc "Match the is_active flag of flow"
    field :is_active, :boolean

    @desc "Match the is_background flag of flow"
    field :is_background, :boolean
  end

  object :flow_queries do
    @desc "get the details of one flow"
    field :flow, :flow_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.flow/3)
    end

    @desc "Get a list of all flows"
    field :flows, list_of(:flow) do
      arg(:filter, :flow_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.flows/3)
    end

    @desc "Get a count of all flows filtered by various criteria"
    field :count_flows, :integer do
      arg(:filter, :flow_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.count_flows/3)
    end

    @desc "Export flow details so that we can import it again"
    field :export_flow, :export_flow do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.export_flow/3)
    end

    @desc "Get a flow for this user"
    field :flow_get, :flow_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.flow_get/3)
    end

    @desc "Release a flow for this user"
    field :flow_release, :flow do
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.flow_release/3)
    end

    @desc "Get broadcast flow stats"
    field :broadcast_stats, :json do
      arg(:flow_boradcast_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.broadcast_stats/3)
    end
  end

  object :flow_mutations do
    field :create_flow, :flow_result do
      arg(:input, non_null(:flow_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.create_flow/3)
    end

    field :update_flow, :flow_result do
      arg(:id, non_null(:id))
      arg(:input, :flow_input)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.update_flow/3)
    end

    field :delete_flow, :flow_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.delete_flow/3)
    end

    field :publish_flow, :common_flow_result do
      arg(:uuid, non_null(:uuid4))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.publish_flow/3)
    end

    field :start_contact_flow, :common_flow_result do
      arg(:flow_id, non_null(:id))
      arg(:contact_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.start_contact_flow/3)
    end

    field :resume_contact_flow, :common_flow_result do
      arg(:flow_id, non_null(:id))
      arg(:contact_id, non_null(:id))
      arg(:result, :json)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.resume_contact_flow/3)
    end

    field :copy_flow, :flow_result do
      arg(:id, non_null(:id))
      arg(:input, :flow_input)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.copy_flow/3)
    end

    field :start_group_flow, :common_flow_result do
      arg(:flow_id, non_null(:id))
      arg(:group_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.start_group_flow/3)
    end

    field :import_flow, :common_flow_result do
      arg(:flow, :json)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.import_flow/3)
    end
  end
end
