defmodule GlificWeb.Resolvers.OpenAI do
  @moduledoc """
  OPENAI Resolver which sits between the GraphQL schema and OPENAI Filesearch API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.OpenAI.ChatGPT

  @doc """
  Create a Vector Store
  """
  @spec create_vector_store(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def create_vector_store(_, %{name: name} = _args, _),
    do: ChatGPT.create_vector_store(name)

  @doc """
  Delete a Vector Store
  """
  @spec delete_vector_store(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def delete_vector_store(_, %{vector_store_id: vector_store_id} = _args, _),
    do: ChatGPT.delete_vector_store(vector_store_id)

  @doc """
  Create an assistant
  """
  @spec create_assistant(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def create_assistant(_, args, _),
    do: ChatGPT.create_assistant(args)

  @doc """
  Delete Assistant
  """
  @spec delete_assistant(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def delete_assistant(_, %{assistant_id: assistant_id} = _args, _),
    do: ChatGPT.delete_assistant(assistant_id)
end
