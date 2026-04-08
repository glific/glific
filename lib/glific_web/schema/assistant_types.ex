defmodule GlificWeb.Schema.AssistantTypes do
  @moduledoc """
  GraphQL Representation of Glific's Assistant DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :knowledge_base_result do
    field :knowledge_base, :vector_store
    field :errors, list_of(:input_error)
  end

  object :vector_store do
    field :id, :id
    field :knowledge_base_version_id, :string
    field :vector_store_id, :string
    field :name, :string

    field :files, list_of(:file_info) do
      resolve(&Resolvers.Filesearch.list_files/3)
    end

    field :size, :string do
      resolve(&Resolvers.Filesearch.calculate_vector_store_size/3)
    end

    field :status, :string
    field :legacy, :boolean

    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :file_info do
    field :id, :string
    field :name, :string
    field :uploaded_at, :string
    field :file_size, :integer
  end

  object :file_result do
    field :file_id, :string
    field :filename, :string
    field :uploaded_at, :string
    field :file_size, :integer
  end

  object :kaapi_assistant_result do
    field :assistant, :kaapi_assistant
    field :errors, list_of(:input_error)
  end

  object :kaapi_assistant do
    field :id, :id
    field :name, :string
    field :description, :string
    field :kaapi_uuid, :string
    field :assistant_display_id, :string
    field :assistant_id, :string
    field :active_config_version_id, :string
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :assistant_result do
    field :assistant, :assistant
    field :errors, list_of(:input_error)
  end

  object :assistant_config_version do
    field :id, :id
    field :version_number, :integer
    field :model, :string
    field :prompt, :string
    field :settings, :json
    field :status, :string
    field :is_live, :boolean
    field :description, :string
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :set_live_version_result do
    field :assistant, :live_version_assistant
    field :errors, list_of(:input_error)
  end

  object :live_version_assistant do
    field :id, :id
    field :active_config_version_id, :id
    field :live_version_number, :integer
  end

  object :assistant do
    field :id, :id
    field :assistant_display_id, :string
    field :name, :string
    field :assistant_id, :string
    field :model, :string
    field :instructions, :string
    field :temperature, :float
    field :status, :string
    field :new_version_in_progress, :boolean
    field :live_version_number, :integer
    field :legacy, :boolean
    field :clone_status, :string
    field :active_config_version_id, :id

    field :vector_store, :vector_store do
      resolve(&Resolvers.Filesearch.resolve_vector_store/3)
    end

    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :clone_result do
    field :message, :string
    field :errors, list_of(:input_error)
  end

  input_object :vector_store_input do
    field :name, :string
  end

  input_object :assistant_input do
    field :name, :string
    field :model, :string
    field :instructions, :string
    field :description, :string
    field :temperature, :float
    field :knowledge_base_version_id, :string
  end

  input_object :file_info_input do
    field :file_id, :string
    field :filename, :string
    field :uploaded_at, :string
    field :file_size, :integer
  end

  @desc "Filtering options for VectorStore"
  input_object :vector_store_filter do
    @desc "Match the name"
    field(:name, :string)
  end

  @desc "Filtering options for Assistants"
  input_object :assistant_filter do
    @desc "Match the name"
    field(:name, :string)
  end

  object :assistant_config_version_for_evals do
    field :id, :id
    field :assistant_id, :id
    field :kaapi_uuid, :string
    field :version_number, :integer
    field :kaapi_version_number, :integer
    field :description, :string
    field :prompt, :string
    field :provider, :string
    field :model, :string
    field :settings, :json
    field :status, :string
    field :assistant_name, :string
    field :failure_reason, :string
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :filesearch_mutations do
    @desc "Upload filesearch file"
    field :upload_filesearch_file, :file_result do
      arg(:media, non_null(:upload))
      arg(:target_format, :string)
      arg(:callback_url, :string)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.upload_file/3)
    end

    @desc "Create Assistant"
    field :create_assistant, :kaapi_assistant_result do
      arg(:input, :assistant_input)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.create_assistant/3)
    end

    @desc "Delete Assistant"
    field :delete_assistant, :kaapi_assistant_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.delete_assistant/3)
    end

    @desc "Create a Knowledge Base Version"
    field :create_knowledge_base, :knowledge_base_result do
      arg(:media_info, non_null(list_of(non_null(:file_info_input))))
      arg(:id, :id)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Assistants.create_knowledge_base/3)
    end

    @desc "Update Assistant"
    field :update_assistant, :assistant_result do
      arg(:input, :assistant_input)
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.update_assistant/3)
    end

    @desc "Clone an existing Assistant"
    field :clone_assistant, :clone_result do
      arg(:id, non_null(:id))
      arg(:version_id, :id)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Assistants.clone_assistant/3)
    end

    @desc "Set a config version as the live version for an assistant"
    field :set_live_version, :set_live_version_result do
      arg(:assistant_id, non_null(:id))
      arg(:version_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.set_live_version/3)
    end
  end

  object :filesearch_queries do
    @desc "Get Assistant"
    field :assistant, :assistant_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.get_assistant/3)
    end

    @desc "List Assistants"
    field :assistants, list_of(:assistant) do
      arg(:filter, :assistant_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.list_assistants/3)
    end

    @desc "List Assistant Config Versions"
    field :assistant_config_versions, list_of(:assistant_config_version_for_evals) do
      middleware(Authorize, :staff)
      resolve(&Resolvers.Assistants.list_assistant_config_versions/3)
    end

    @desc "Get a count of all assistants filtered by various criteria"
    field :count_assistants, :integer do
      arg(:filter, :assistant_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.count_assistants/3)
    end

    @desc "List models"
    field :list_openai_models, list_of(:string) do
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.list_models/3)
    end

    @desc "List all config versions for an assistant"
    field :assistant_versions, list_of(:assistant_config_version) do
      arg(:assistant_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.list_assistant_versions/3)
    end
  end
end
