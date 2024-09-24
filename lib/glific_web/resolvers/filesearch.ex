defmodule GlificWeb.Resolvers.Filesearch do
  @moduledoc """
  Filesearch Resolver which sits between the GraphQL schema and Glific Filesearch API.
  """
  alias Glific.Filesearch

  @doc """
  Create a Vector Store

  Returns a Vector Store struct
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
  Uploads a file to openAI
  Returns the File details
  """
  @spec upload_file(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def upload_file(_, params, %{context: %{current_user: _user}}) do
    Filesearch.upload_file(params)
  end

  @spec update_vector_store_files(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_vector_store_files(_, %{input: params}, %{context: %{current_user: _user}}) do
    Filesearch.update_vector_store_files(params)
  end
end
