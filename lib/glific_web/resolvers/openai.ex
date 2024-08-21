defmodule GlificWeb.Resolvers.OpenAI do
  @moduledoc """
  OPENAI Resolver which sits between the GraphQL schema and OPENAI Filesearch API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.OpenAI.{VectorStore, Assistant, ChatGPT}
  alias Glific.Repo

  @doc """
  Create a Vector Store
  """
  @spec create_vector_store(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_vector_store(_, %{name: vector_store_name}, %{context: %{current_user: user}}) do
    {:ok, %{vector_store_id: store_id}} = ChatGPT.create_vector_store(vector_store_name)

    VectorStore.record_vector_store(%{
      vector_store_id: store_id,
      organization_id: user.organization_id,
      vector_store_name: vector_store_name
    })

    {:ok, %{vector_store_id: store_id}}
  end

  @doc """
  Delete a Vector Store
  """
  @spec delete_vector_store(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def delete_vector_store(_, %{vector_store_id: vector_store_id} = _args, _) do
    with {:ok, %{vector_store_id: vector_store_id}} <-
           ChatGPT.delete_vector_store(vector_store_id),
         {:ok, openai_vector_store} <- Repo.fetch_by(VectorStore, %{vector_store_id: vector_store_id}) do
      VectorStore.delete_vector_store_record(openai_vector_store)
    end

    {:ok, %{vector_store_id: vector_store_id}}
  end

  @doc """
  Create an assistant
  """
  @spec create_assistant(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def create_assistant(_, params, %{context: %{current_user: user}}) do
    {:ok, %{assistant_id: assistant_id}} = ChatGPT.create_assistant(params)

    Assistant.record_assistant(%{
      assistant_id: assistant_id,
      assistant_name: params.name,
      model: params.model,
      vector_store_id: params.vector_store_id,
      description: params.description,
      instructions: params.instructions,
      organization_id: user.organization_id
    })

    {:ok, %{assistant_id: assistant_id}}
  end

  @doc """
  Delete Assistant
  """
  @spec delete_assistant(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def delete_assistant(_, %{assistant_id: assistant_id} = _args, _) do
    with {:ok, %{assistant_id: assistant_id}} <- ChatGPT.delete_assistant(assistant_id),
         {:ok, openai_assistant} <- Repo.fetch_by(Assistant, %{assistant_id: assistant_id}) do
      Assistant.delete_assistant_record(openai_assistant)
    end

    {:ok, %{assistant_id: assistant_id}}
  end
end
