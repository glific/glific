defmodule GlificWeb.Resolvers.Filesearch do
  @moduledoc """
  Filesearch Resolver which sits between the GraphQL schema and Glific Filesearch API.
  """
  alias Glific.Filesearch.VectorStore
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
  def update_vector_store_files(_, params, %{context: %{current_user: _user}}) do
    with {:ok, vector_store} <- Filesearch.update_vector_store_files(params) do
      {:ok, %{vector_store: vector_store}}
    end
  end

  def add_vector_store_files(_, params, %{context: %{current_user: user}}) do
    params = Map.put(params, :organization_id, user.organization_id)

    with {:ok, vector_store} <- Filesearch.add_vector_store_files(params) do
      {:ok, %{vector_store: vector_store}}
    end
  end

  @spec list_files(VectorStore.t(), map(), map()) :: {:ok, list()}
  def list_files(vector_store, _args, _context) do
    Enum.map(vector_store.files, fn {file_id, file_details} ->
      %{id: file_id, info: file_details}
    end)
    |> IO.inspect()
    |> then(&{:ok, &1})
  end
end
