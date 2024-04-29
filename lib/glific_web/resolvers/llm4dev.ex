defmodule GlificWeb.Resolvers.LLM4Dev do
  @moduledoc """
  LLM4Dev Resolver which sits between the GraphQL schema and Glific LLM4Dev Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.LLM4Dev

  @doc """
  Get the list of groups filtered by args
  """
  @spec knowledge_bases(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, list()} | {:error, any()}
  def knowledge_bases(_, %{organization_id: organization_id} = _args, _),
    do: LLM4Dev.list_knowledge_base(organization_id)

  @doc """
  Get the list of groups filtered by args
  """
  @spec categories(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, list()} | {:error, any()}
  def categories(_, %{organization_id: organization_id} = _args, _),
    do: LLM4Dev.list_categories(organization_id)

  @doc """
  Delete a knowledge base file
  """
  @spec delete_knowledge_base(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def delete_knowledge_base(_, args, _),
    do: LLM4Dev.delete_knowledge_base(args.organization_id, args.uuid)

  @doc """
  Upload a pdf file as knowledge base
  """
  @spec upload_knowledge_base(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def upload_knowledge_base(_, args, _),
    do: LLM4Dev.upload_knowledge_base(args.organization_id, args)

  @doc """
  Create a new category
  """
  @spec create_category(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def create_category(_, args, _),
    do: LLM4Dev.create_category(args.organization_id, args)
end
