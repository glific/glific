defmodule GlificWeb.Resolvers.Filesearch do
  @moduledoc """
  Filesearch Resolver which sits between the GraphQL schema and Glific Filesearch API.
  """
  alias Glific.Filesearch

  @doc """
  Create a Vector Store
  """
  @spec create_vector_store(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_vector_store(_, %{input: params}, %{context: %{current_user: user}}) do
    attrs = %{
      organization_id: user.organization_id,
      name: params.name,
      files: %{}
    }

    Filesearch.create_vector_store(attrs)
  end

  @doc """
  Create a Vector Store
  """
  @spec upload_knowledge_base(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def upload_knowledge_base(_, params, %{context: %{current_user: _user}}) do
    Filesearch.upload_knowledge_base(params)
    {:ok, "success"}
  end
end
