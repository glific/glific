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

    field :assistants, list_of(:assistant) do
      resolve(dataloader(Repo))
    end

    field :size, :string do
      resolve(&Resolvers.Filesearch.calculate_vector_store_size/3)
    end

    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  object :file_info do
    field :id, :string
    field :name, :string
    field :size, :integer
  end

  object :file_result do
    field :file_id, :string
    field :filename, :string
    field :size, :integer
  end

  object :assistant do
    field :id, :id
    field :name, :string
    field :model, :string
    field :instructions, :string
    # field :settings
  end

  input_object :vector_store_input do
    field :name, :string
  end

  @desc "Filtering options for VectorStore"
  input_object :vector_store_filter do
    @desc "Match the name"
    field(:name, :string)
  end

  object :filesearch_mutations do
    @desc "Create vector store"
    field :create_vector_store, :vector_store_result do
      arg(:input, :vector_store_input)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.create_vector_store/3)
    end

    @desc "Upload filesearch file"
    field :upload_filesearch_file, :file_result do
      arg(:media, non_null(:upload))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.upload_file/3)
    end

    @desc "Add files to vector store"
    field :add_vector_store_files, :vector_store_result do
      arg(:media, non_null(list_of(non_null(:upload))))
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.add_vector_store_files/3)
    end

    @desc "Remove files from vector store"
    field :remove_vector_store_file, :vector_store_result do
      arg(:file_id, non_null(:string))
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.remove_vector_store_file/3)
    end

    @desc "Update Vector store"
    field :update_vector_store, :vector_store_result do
      arg(:input, non_null(:vector_store_input))
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.update_vector_store/3)
    end

    @desc "Delete Vector store"
    field :delete_vector_store, :vector_store_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.delete_vector_store/3)
    end
  end

  object :filesearch_queries do
    @desc "Get vector store"
    field :vector_store, :vector_store_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.get_vector_store/3)
    end

    @desc "List vector stores"
    field :vector_stores, list_of(:vector_store) do
      arg(:filter, :vector_store_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.list_vector_stores/3)
    end
  end
end
