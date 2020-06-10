defmodule GlificWeb.Resolvers.Conversations do
  @moduledoc """
  Tag Resolver which sits between the GraphQL schema and Glific Conversation Context API.
  This layer basically stiches together one or more calls to resolve the incoming queries.
  """

  alias Glific.Conversations

  @doc """
  Get the list of conversations filtered by args
  """
  @spec conversations(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def conversations(_, args, _) do
    {:ok, Conversations.list_conversations(args)}
  end
end
