defmodule GlificWeb.Resolvers.Assistants do
  @moduledoc """
  Assistant Resolver which sits between the GraphQL schema and Glific Assistants Context API.
  This layer basically stitches together one or more calls to resolve the incoming queries.
  """

  alias Glific.Assistants

  @doc """
  Create a new knowledge base with the given parameters.
  """
  @spec create_knowledge_base(map(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def create_knowledge_base(_, params, _context) do
    with {:ok, %{knowledge_base_version: knowledge_base_version, knowledge_base: knowledge_base}} <-
           Assistants.create_knowledge_base_with_version(params) do
      response = %{
        id: knowledge_base.id,
        name: knowledge_base.name,
        llm_service_id: knowledge_base_version.llm_service_id,
        files: knowledge_base_version.files,
        size: knowledge_base_version.size,
        status: knowledge_base_version.status,
        inserted_at: knowledge_base.inserted_at,
        updated_at: knowledge_base_version.inserted_at
      }

      {:ok, %{knowledge_base: response}}
    end
  end
end
