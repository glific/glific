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
  def knowledge_bases(_, %{organization_id: organization_id} = _args, _),
    do: LLM4Dev.list_knowledge_base(organization_id)

  @spec delete_knowledge_base(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [Group]}
  def delete_knowledge_base(_, args, _) do
    LLM4Dev.delete_knowledge_base(args.organization_id, args.uuid)
  end
end
