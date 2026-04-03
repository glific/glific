defmodule Glific.AskmeBot do
  @moduledoc """
  Glific AskMeBot context module for business logic.
  """

  import Ecto.Query, warn: false

  alias Glific.AskmeBot.Conversation
  alias Glific.Dify.ApiClient
  alias Glific.Repo

  @doc """
  Calls the Dify chat-messages API and fetches the answer for AskMe bot.
  Supports conversation history via conversation_id.
  """
  @spec askme(map(), map()) ::
          {:ok, map()} | {:error, String.t()}
  def askme(params, user) do
    Glific.Metrics.increment("AskMeBot Requests")

    query = Map.get(params, :query)
    conversation_id = Map.get(params, :conversation_id, "")
    page_url = Map.get(params, :page_url, "")

    body = %{
      "inputs" => %{"page_url" => page_url},
      "query" => query,
      "response_mode" => "blocking",
      "conversation_id" => conversation_id,
      "user" => dify_user(user)
    }

    is_new_conversation = conversation_id == ""

    case ApiClient.chat_messages(body, dify_api_key()) do
      {:ok, response} ->
        answer = Map.get(response, "answer", "")
        resp_conversation_id = Map.get(response, "conversation_id", "")

        create_conversation(resp_conversation_id, user)

        conversation_name =
          if is_new_conversation do
            generate_conversation_name(resp_conversation_id, user)
          else
            nil
          end

        {:ok,
         %{
           answer: answer,
           conversation_id: resp_conversation_id,
           conversation_name: conversation_name
         }}

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

  @doc """
  Fetches conversations from Dify for the given user.
  Dify scopes results by the user identifier, so no additional filtering is needed.
  """
  @spec get_conversations(map(), map()) ::
          {:ok, map()} | {:error, String.t()}
  def get_conversations(user, params \\ %{}) do
    limit = Map.get(params, :limit, 20)
    last_id = Map.get(params, :last_id, "")

    case ApiClient.conversations(dify_user(user), dify_api_key(), limit, last_id) do
      {:ok, response} ->
        conversations =
          response
          |> Map.get("data", [])
          |> Enum.map(&parse_conversation/1)

        {:ok,
         %{
           conversations: conversations,
           has_more: Map.get(response, "has_more", false),
           limit: Map.get(response, "limit", limit)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches messages for a conversation from Dify.
  Only allowed if the conversation is tracked in our database for this user.
  """
  @spec get_messages(String.t(), map(), map()) ::
          {:ok, map()} | {:error, String.t()}
  def get_messages(conversation_id, user, params \\ %{}) do
    limit = Map.get(params, :limit, 20)
    first_id = Map.get(params, :first_id, "")

    if conversation_owned_by_user?(conversation_id, user.id) do
      case ApiClient.messages(conversation_id, dify_user(user), dify_api_key(), limit, first_id) do
        {:ok, response} ->
          messages =
            response
            |> Map.get("data", [])
            |> Enum.map(&parse_message/1)

          {:ok,
           %{
             messages: messages,
             has_more: Map.get(response, "has_more", false),
             limit: Map.get(response, "limit", limit)
           }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "Conversation not found"}
    end
  end

  @spec conversation_owned_by_user?(String.t(), non_neg_integer()) :: boolean()
  defp conversation_owned_by_user?(conversation_id, user_id) do
    Conversation
    |> where([c], c.conversation_id == ^conversation_id and c.user_id == ^user_id)
    |> Repo.exists?()
  end

  defp parse_message(msg) do
    %{
      id: Map.get(msg, "id", ""),
      conversation_id: Map.get(msg, "conversation_id", ""),
      query: Map.get(msg, "query", ""),
      answer: Map.get(msg, "answer", ""),
      created_at: Map.get(msg, "created_at", 0)
    }
  end

  defp parse_conversation(conv) do
    %{
      id: Map.get(conv, "id", ""),
      name: Map.get(conv, "name", ""),
      status: Map.get(conv, "status", ""),
      created_at: Map.get(conv, "created_at", 0),
      updated_at: Map.get(conv, "updated_at", 0)
    }
  end

  @spec generate_conversation_name(String.t(), map()) :: String.t() | nil
  defp generate_conversation_name(conversation_id, user) do
    case ApiClient.auto_generate_conversation_name(
           conversation_id,
           dify_user(user),
           dify_api_key()
         ) do
      {:ok, response} -> Map.get(response, "name")
      {:error, _reason} -> nil
    end
  end

  @spec dify_user(map()) :: String.t()
  defp dify_user(user), do: "org-#{user.organization_id}-user-#{user.id}"

  @spec dify_api_key() :: String.t()
  defp dify_api_key, do: Application.get_env(:glific, :dify_api_key, "")
end
