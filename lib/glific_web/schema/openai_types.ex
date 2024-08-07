defmodule GlificWeb.Schema.OpenAITypes do
  @moduledoc """
  GraphQL Representation of Glific's OpenAI DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :vector_store do
    field :name, :string
    field :id, :string
  end

  object :assistant do
    field :name, :string
    field :description, :string
    field :instructions, :string
    field :vector_store_id, :string
    field :model, :string
    field :assistant_id, :string
  end

  object :openai_mutations do
    @desc "Create vector store"
    field :create_vector_store, :vector_store do
      arg(:name, non_null(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.OpenAI.create_vector_store/3)
    end

    @desc "Delete vector store"
    field :delete_vector_store, :vector_store do
      arg(:id, non_null(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.OpenAI.delete_vector_store/3)
    end

    @desc "Create Assistant"
    field :create_assistant, :assistant do
      arg(:name, non_null(:string))
      arg(:model, non_null(:string))
      arg(:description, :string)
      arg(:instructions, :string)
      arg(:vector_store_id, non_null(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.OpenAI.create_assistant/3)
    end

    @desc "Delete a knowledgebase"
    field :delete_assistant, :assistant do
      arg(:assistant_id, non_null(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.OpenAI.delete_assistant/3)
    end
  end
end
