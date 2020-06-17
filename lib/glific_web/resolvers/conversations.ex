defmodule GlificWeb.Resolvers.Conversations do
  @moduledoc """
  Tag Resolver which sits between the GraphQL schema and Glific Conversation Context API.
  This layer basically stiches together one or more calls to resolve the incoming queries.
  """

  alias Glific.Conversations

  @doc """
  Get a specific conversation by contact id
  """
  @spec conversation(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def conversation(_, args, _) do
    {:ok, Conversations.conversation_by_id(args)}
  end

  @doc """
  Get the list of conversations filtered by args
  For an authenticated session, we can get the current user from the context via this pattern match
  %{context: %{current_user: current_user}}
  """
  @spec conversations(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def conversations(_, args, _) do
    {:ok, Conversations.list_conversations(args)}
  end
end
