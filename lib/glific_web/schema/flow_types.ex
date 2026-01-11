defmodule GlificWeb.Schema.FlowTypes do
  @moduledoc """
  GraphQL Representation of Flow DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1, dataloader: 2]
  alias Glific.Repo
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

  object :publish_flow_result do
    field :success, :boolean
    field :errors, list_of(:publish_flow_error)
  end

  object :publish_flow_error do
    field :key, non_null(:string)
    field :message, non_null(:string)
    field :category, non_null(:string)
  end

  object :export_flow do
    field :export_data, :json
    field :errors, list_of(:input_error)
  end

  object :export_flow_localization do
    field :export_data, :string
  end

  object :import_flow_result do
    field :status, list_of(:import_flow_status)
  end

  object :import_flow_status do
    field :flow_name, non_null(:string)
    field :status, non_null(:string)
  end

  object :text_to_flow_result do
    field :success, :boolean
    field :flow_data, :json
    field :errors, list_of(:input_error)
  end

  object :flow do
    field :id, :id
    field :uuid, :uuid4
    field :name, :string
    field :keywords, list_of(:string)
    field :ignore_keywords, :boolean
    field :is_active, :boolean
    field :is_template, :boolean
    field :skip_validation, :boolean
    field :version_number, :string
    field :flow_type, :flow_type_enum
    field :inserted_at, :datetime
    field :updated_at, :datetime
    field :last_published_at, :datetime
    field :last_changed_at, :datetime
    field :is_background, :boolean
    field :description, :string

    field :roles, list_of(:access_role) do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :tag, :tag do
      resolve(dataloader(Repo))
    end

    field :is_pinned, :boolean
  end

  input_object :flow_input do
    field :name, :string
    field :keywords, list_of(:string)
    field :tag_id, :id
    field :ignore_keywords, :boolean
    field :is_active, :boolean
    field :is_background, :boolean
    field :add_role_ids, list_of(:id)
    field :delete_role_ids, list_of(:id)
    field :is_pinned, :boolean
    field :is_template, :boolean
    field :skip_validation, :boolean
    field :description, :string
  end

  @desc "Filtering options for flows"
  input_object :flow_filter do
    @desc "Match the name"
    field(:name, :string)

    @desc "Match the name or keyword or tags"
    field(:name_or_keyword_or_tags, :string)

    @desc "Match the tag_ids"
    field(:tag_ids, list_of(:integer))

    @desc "Match the keyword"
    field(:keyword, :string)

    @desc "Match the uuid"
    field(:uuid, :uuid4)

    @desc "Match the status of flow revision"
    field(:status, :string)

    @desc "Match the is_active flag of flow"
    field(:is_active, :boolean)

    @desc "Match the is_template flag of flow"
    field(:is_template, :boolean)

    @desc "Match the is_background flag of flow"
    field(:is_background, :boolean)

    @desc "Match the is_pinned flag of flow"
    field(:is_pinned, :boolean)
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
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.count_flows/3)
    end

    @desc "Export flow details so that we can import it again"
    field :export_flow, :export_flow do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.export_flow/3)
    end

    @desc "Export flow localization so users can check and translate offline"
    field :export_flow_localization, :export_flow_localization do
      arg(:id, non_null(:id))
      arg(:add_translation, :boolean)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.export_flow_localization/3)
    end

    @desc "Get a flow for this user"
    field :flow_get, :flow_result do
      arg(:id, non_null(:id))
      arg(:is_forced, :boolean)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.flow_get/3)
    end

    @desc "Release a flow for this user"
    field :flow_release, :flow do
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.flow_release/3)
    end

    @desc "Get broadcast flow stats"
    field :broadcast_stats, :json do
      arg(:message_broadcast_id, non_null(:id))
      middleware(Authorize, :manager)
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

    field :publish_flow, :publish_flow_result do
      arg(:uuid, non_null(:uuid4))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.publish_flow/3)
    end

    field :start_contact_flow, :common_flow_result do
      arg(:flow_id, non_null(:id))
      arg(:contact_id, non_null(:id))
      arg(:default_results, :json)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.start_contact_flow/3)
    end

    field :start_wa_group_flow, :common_flow_result do
      arg(:flow_id, non_null(:id))
      arg(:wa_group_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.start_wa_group_flow/3)
    end

    field :resume_contact_flow, :common_flow_result do
      arg(:flow_id, non_null(:id))
      arg(:contact_id, non_null(:id))
      arg(:result, :json)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.resume_contact_flow/3)
    end

    field :copy_flow, :flow_result do
      arg(:id, non_null(:id))
      arg(:input, :flow_input)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.copy_flow/3)
    end

    field :reset_flow_count, :common_flow_result do
      arg(:flow_id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.reset_flow_count/3)
    end

    field :terminate_contact_flows, :common_flow_result do
      arg(:contact_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Flows.terminate_contact_flows/3)
    end

    field :start_group_flow, :common_flow_result do
      arg(:flow_id, non_null(:id))
      arg(:group_id, non_null(:id))
      arg(:default_results, :json)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.start_group_flow/3)
    end

    field :start_wa_group_collection_flow, :common_flow_result do
      arg(:flow_id, non_null(:id))
      arg(:group_id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.start_wa_group_collection_flow/3)
    end

    field :import_flow, :import_flow_result do
      arg(:flow, :json)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.import_flow/3)
    end

    field :import_flow_localization, :common_flow_result do
      arg(:localization, :string)
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.import_flow_localization/3)
    end

    field :inline_flow_localization, :common_flow_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.inline_flow_localization/3)
    end

    field :generate_flow_from_text, :text_to_flow_result do
      arg(:uuid, non_null(:uuid4))
      arg(:prompt, non_null(:string))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Flows.generate_flow_from_text/3)
    end
  end
end
