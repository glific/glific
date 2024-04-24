defmodule GlificWeb.Schema.LLM4DevTypes do
  @moduledoc """
  GraphQL Representation of Glific's LLM4Dev DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :category do
    field :name, :string
    field :uuid, :uuid4
    field :id, :id
  end

  object :knowledge_base do
    field :name, :string
    field :uuid, :uuid4
    field :category, :category
  end

  object :knowledge_base_result do
    field :knowledge_base, list_of(:knowledge_base)
  end

  object :llm_result do
    field :msg, :string
  end

  object :llm4dev_queries do
    @desc "Get a list of all knowledge bases"
    field :knowledge_bases, :knowledge_base_result do
      middleware(Authorize, :staff)
      resolve(&Resolvers.LLM4Dev.knowledge_bases/3)
    end
  end

  object :llm4dev_mutations do
    @desc "Delete a knowledgebase"
    field :delete_knowledge_base, :llm_result do
      arg(:uuid, non_null(:uuid4))
      middleware(Authorize, :staff)
      resolve(&Resolvers.LLM4Dev.delete_knowledge_base/3)
    end

    @desc "Upload knowledgebase"
    field :upload_knowledge_base, :llm_result do
      arg(:media, non_null(:upload))
      arg(:category_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.LLM4Dev.upload_knowledge_base/3)
    end
  end
end
