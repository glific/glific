defmodule Glific.AskGlific do
  @moduledoc """
  Glific AskGlific context module for business logic.
  """

  alias Glific.AskGlific.Conversation
  alias Glific.Dify.ApiClient
  alias Glific.Repo

  @doc """
  Calls the Dify chat-messages API and fetches the answer for AskGlific bot.
  Supports conversation history via conversation_id.
  """
  @spec ask(map(), map()) ::
          {:ok, map()} | {:error, String.t()}
  def ask(params, user) do
    Glific.Metrics.increment("AskGlific Requests")

    query = Map.get(params, :query)
    conversation_id = Map.get(params, :conversation_id, "")
    page_url = Map.get(params, :page_url, "")

    body = %{
      "inputs" => %{"page_url" => page_url},
      "query" => query,
      "response_mode" => "blocking",
      "conversation_id" => conversation_id,
      "user" => "org-#{user.organization_id}-user-#{user.id}"
    }

    case ApiClient.chat_messages(body, dify_api_key()) do
      {:ok, response} ->
        answer = Map.get(response, "answer", "")
        resp_conversation_id = Map.get(response, "conversation_id", "")

        create_conversation(resp_conversation_id, user)

        {:ok, %{answer: answer, conversation_id: resp_conversation_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec create_conversation(String.t(), map()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  defp create_conversation(conversation_id, user) do
    %Conversation{}
    |> Conversation.changeset(%{
      conversation_id: conversation_id,
      user_id: user.id,
      organization_id: user.organization_id
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  @spec dify_api_key() :: String.t()
  defp dify_api_key, do: Application.get_env(:glific, :dify_api_key, "")
end
