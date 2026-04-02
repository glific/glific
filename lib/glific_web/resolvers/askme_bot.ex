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
  Fetch message history for a conversation from Dify
  """
  @spec messages(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any}
  def messages(_, %{conversation_id: _conversation_id}, %{context: %{current_user: _user}}) do
    # add the message history logic
    {:ok, %{}}
  end
end
