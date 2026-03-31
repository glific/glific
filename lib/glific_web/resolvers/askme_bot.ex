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
    dify_params = %{
      "query" => Map.get(params, :query, ""),
      "conversation_id" => Map.get(params, :conversation_id, "")
    }

    case AskmeBot.askme(dify_params, user.organization_id) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
