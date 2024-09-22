defmodule GlificWeb.Schema.FilesearchTypes do
  @moduledoc """
  GraphQL Representation of Glific's Filesearch DataType
  """
  use Absinthe.Schema.Notation
  # import Absinthe.Resolution.Helpers

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :vector_store_result do
    field :vector_store, :vector_store
    field :errors, list_of(:input_error)
  end

  object :vector_store do
    field :vector_store_id, :string
    field :name, :string
    # field :files, :map

    # field :assistants, list_of(:assistant) do
    #   resolve(dataloader(Repo, use_parent: true))
    # end
  end

  input_object :vector_store_input do
    field :name, :string
  end

  object :filesearch_mutations do
    @desc "Create vector store"
    field :create_vector_store, :vector_store_result do
      arg(:input, non_null(:vector_store_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.create_vector_store/3)
    end
  end
end
