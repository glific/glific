defmodule GlificWeb.Schema.FilesearchTypes do
  @moduledoc """
  GraphQL Representation of Glific's Filesearch DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :vector_store do
    field :name, :string
    field :vector_store_id, :string
  end

  object :assistant_result do
    field :assistant, :assistant
    field :errors, list_of(:input_error)
  end

  object :assistant do
    field :name, :string
    field :instructions, :string
    field :vector_store_id, :string
    field :model, :string
    field :assistant_id, :string
  end

  input_object :assistant_input do
    field :name, :string
    field :instructions, :string
    field :vector_store_id, :string
    field :model, :string
    field :assistant_id, :string
  end

  object :filesearch_mutations do
    @desc "Create vector store"
    field :create_vector_store, :vector_store do
      arg(:name, non_null(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.create_vector_store/3)
    end

    @desc "Modify vector sotre"
    field :modify_vector_store, :vector_store do
      arg(:vector_store_id, non_null(:string))
      arg(:name, non_null(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.modify_vector_store/3)
    end

    @desc "Delete vector store"
    field :delete_vector_store, :vector_store do
      arg(:vector_store_id, non_null(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.delete_vector_store/3)
    end

    @desc "Create Assistant"
    field :create_assistant, :assistant_result do
      arg(:input, non_null(:assistant_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.create_assistant/3)
    end

    @desc "Modify Assistant"
    field :modify_assistant, :assistant do
      arg(:assistant_id, non_null(:string))
      arg(:name, non_null(:string))
      arg(:model, non_null(:string))
      arg(:instructions, :string)
      arg(:vector_store_id, :string)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.modify_assistant/3)
    end

    @desc "Delete assistant"
    field :delete_assistant, :assistant do
      arg(:assistant_id, non_null(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.delete_assistant/3)
    end
  end
end
