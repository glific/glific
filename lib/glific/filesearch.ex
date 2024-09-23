defmodule Glific.Filesearch do
  @moduledoc """
  Main module to interact with filesearch
  """
  alias Glific.Filesearch.VectorStore
  alias Glific.OpenAI.Filesearch.ApiClient

  @spec create_vector_store(map()) :: {:ok, map()} | {:error, String.t()}
  def create_vector_store(params) do
    with {:ok, %{id: store_id}} <- ApiClient.create_vector_store(params.name),
         {:ok, vector_store} <-
           VectorStore.create_vector_store(Map.put(params, :vector_store_id, store_id)) do
      {:ok, %{vector_store: vector_store}}
    else
      {:error, _} ->
        {:error, "Vector store creation failed"}
    end
  end

  @doc """
    Set document as knowledge base with category
  """
  @spec upload_knowledge_base(map()) ::
          {:ok, map()} | {:error, String.t()}
  def upload_knowledge_base(params) do
    ApiClient.upload_knowledge_base(params)
  end
end
