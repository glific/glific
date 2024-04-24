defmodule GlificWeb.Resolvers.LLM4Dev do
  @moduledoc """
  LLM4Dev Resolver which sits between the GraphQL schema and Glific LLM4Dev Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.LLM4Dev

  @doc """
  Get the list of groups filtered by args
  """
  @spec knowledge_bases(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [Group]}
  def knowledge_bases(_, args, _), do: LLM4Dev.list_knowledge_base(args.organization_id)
end
