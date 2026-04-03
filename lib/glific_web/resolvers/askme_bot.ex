defmodule GlificWeb.Resolvers.AskmeBot do
  @moduledoc """
  AskMe Bot Resolver which sits between the GraphQL schema and Glific AskmeBot module.
  """

  alias Glific.AskmeBot

  @doc """
  Ask the AskMe bot a question and get an answer
  """
  @spec ask(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, map()} | {:error, any}
  def ask(_, %{input: params}, %{context: %{current_user: user}}) do
    case AskmeBot.askme(params, user) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches conversations from Dify for the current user.
  """
  @spec get_conversations(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any}
  def get_conversations(_, args, %{context: %{current_user: user}}) do
    AskmeBot.get_conversations(user, args)
  end

  @doc """
  Fetch message history for a conversation from Dify.
  """
  @spec messages(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any}
  def messages(_, %{conversation_id: conversation_id} = args, %{context: %{current_user: user}}) do
    AskmeBot.get_messages(conversation_id, user, args)
  end
end
