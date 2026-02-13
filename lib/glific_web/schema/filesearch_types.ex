defmodule GlificWeb.Schema.FilesearchTypes do
  @moduledoc """
  GraphQL Representation of Glific's Filesearch DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :vector_store_result do
    field :vector_store, :vector_store
    field :errors, list_of(:input_error)
  end

  object :vector_store do
    field :id, :id
    field :vector_store_id, :string
    field :name, :string

    field :files, list_of(:file_info) do
      resolve(&Resolvers.Filesearch.list_files/3)
    end

    field :size, :string do
      resolve(&Resolvers.Filesearch.calculate_vector_store_size/3)
    end

    field :status, :string

    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :file_info do
    field :id, :string
    field :name, :string
    field :uploaded_at, :string
  end

  object :file_result do
    field :file_id, :string
    field :filename, :string
    field :uploaded_at, :string
  end

  object :assistant_result do
    field :assistant, :assistant
    field :errors, list_of(:input_error)
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

  object :assistant do
    field :id, :id
    field :name, :string
    field :assistant_id, :string
    field :model, :string
    field :instructions, :string
    field :temperature, :float

    field :vector_store, :vector_store do
      resolve(dataloader(Repo))
    end

    field :inserted_at, :datetime
    field :updated_at, :datetime
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
    field :knowledge_base_id, :string
  end

  input_object :file_info_input do
    field :file_id, :string
    field :filename, :string
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
    field :delete_assistant, :assistant_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.delete_assistant/3)
    end

    @desc "Add files to Assistant"
    field :add_assistant_files, :assistant_result do
      arg(:media_info, non_null(list_of(non_null(:file_info_input))))
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.add_assistant_files/3)
    end

    @desc "Remove files from Assistant"
    field :remove_assistant_file, :assistant_result do
      arg(:file_id, non_null(:string))
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.remove_assistant_file/3)
    end

    @desc "Update Assistant"
    field :update_assistant, :assistant_result do
      arg(:input, :assistant_input)
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.update_assistant/3)
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

    @desc "List models"
    field :list_openai_models, list_of(:string) do
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.list_models/3)
    end
  end
end
