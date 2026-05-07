defmodule Glific.AskGlific do
  @moduledoc """
  Glific AskGlific context module for business logic.
  """

  import Ecto.Query, warn: false

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
      "user" => dify_user(user)
    }

    is_new_conversation = conversation_id == ""

    case ApiClient.chat_messages(body) do
      {:ok, response} ->
        answer = Map.get(response, "answer", "")
        resp_conversation_id = Map.get(response, "conversation_id", "")
        message_id = Map.get(response, "message_id", "")

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
           conversation_name: conversation_name,
           message_id: message_id
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Submits feedback (like/dislike) for a Dify message.
  """
  @spec submit_feedback(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def submit_feedback(params, user) do
    message_id = Map.get(params, :message_id)
    rating = Map.get(params, :rating)
    content = Map.get(params, :content, "")

    body = %{
      "rating" => rating,
      "user" => dify_user(user),
      "content" => content
    }

    case ApiClient.message_feedback(message_id, body) do
      {:ok, _response} ->
        {:ok, %{success: true}}

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
  Fetches conversations from Dify for the given user, restricted to those
  also tracked in our database for this user.
  """
  @spec get_conversations(map(), map()) ::
          {:ok, map()} | {:error, String.t()}
  def get_conversations(user, params \\ %{}) do
    limit = Map.get(params, :limit, 20)
    last_id = Map.get(params, :last_id, "")

    case ApiClient.conversations(dify_user(user), limit, last_id) do
      {:ok, response} ->
        dify_conversations = Map.get(response, "data", [])
        dify_ids = Enum.map(dify_conversations, &Map.get(&1, "id", ""))
        tracked_ids = tracked_conversation_ids(user.id, dify_ids)

        conversations =
          dify_conversations
          |> Enum.filter(fn conv -> MapSet.member?(tracked_ids, Map.get(conv, "id", "")) end)
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

  @spec tracked_conversation_ids(non_neg_integer(), [String.t()]) :: MapSet.t()
  defp tracked_conversation_ids(_user_id, []), do: MapSet.new()

  defp tracked_conversation_ids(user_id, conversation_ids) do
    Conversation
    |> where([c], c.user_id == ^user_id and c.conversation_id in ^conversation_ids)
    |> select([c], c.conversation_id)
    |> Repo.all()
    |> MapSet.new()
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
      case ApiClient.messages(conversation_id, dify_user(user), limit, first_id) do
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
    feedback = msg |> Map.get("feedback", nil) |> parse_feedback()

    %{
      id: Map.get(msg, "id", ""),
      conversation_id: Map.get(msg, "conversation_id", ""),
      query: Map.get(msg, "query", ""),
      answer: Map.get(msg, "answer", ""),
      created_at: Map.get(msg, "created_at", 0),
      feedback: feedback
    }
  end

  defp parse_feedback(nil), do: nil
  defp parse_feedback(%{"rating" => rating}) when rating in ["like", "dislike"], do: rating
  defp parse_feedback(_), do: nil

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
           dify_user(user)
         ) do
      {:ok, response} -> Map.get(response, "name")
      {:error, _reason} -> nil
    end
  end

  @spec dify_user(map()) :: String.t()
  defp dify_user(user), do: "org-#{user.organization_id}-user-#{user.id}"
end
