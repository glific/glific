defmodule GlificWeb.Resolvers.AskmeBotTest do
  @moduledoc """
  Test suite for AskMe Bot GraphQL resolvers.
  """
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.AskGlific.Conversation
  alias Glific.Repo

  load_gql(
    :askme_bot,
    GlificWeb.Schema,
    "assets/gql/ask_glific/ask.gql"
  )

  load_gql(
    :conversations,
    GlificWeb.Schema,
    "assets/gql/ask_glific/conversations.gql"
  )

  load_gql(
    :messages,
    GlificWeb.Schema,
    "assets/gql/ask_glific/messages.gql"
  )

  load_gql(
    :feedback,
    GlificWeb.Schema,
    "assets/gql/ask_glific/feedback.gql"
  )

  setup do
    test_pid = self()

    Application.put_env(:glific, :dify_req_plug, {Req.Test, test_pid})
    Application.put_env(:glific, :dify_api_key, "test-api-key")

    on_exit(fn ->
      Application.delete_env(:glific, :dify_req_plug)
      Application.delete_env(:glific, :dify_api_key)
    end)

    :ok
  end

  defp insert_conversation(conversation_id, user) do
    %Conversation{}
    |> Conversation.changeset(%{
      conversation_id: conversation_id,
      user_id: user.id,
      organization_id: user.organization_id
    })
    |> Repo.insert!()
  end

  describe "askme_bot mutation" do
    test "returns answer and conversation_id on success", %{staff: user} do
      Req.Test.stub(self(), fn conn ->
        case conn.request_path do
          "/v1/chat-messages" ->
            Req.Test.json(conn, %{
              "answer" => "Glific is great!",
              "conversation_id" => "conv-gql-123"
            })

          "/v1/conversations/conv-gql-123/name" ->
            Req.Test.json(conn, %{"name" => "About Glific"})
        end
      end)

      {:ok, query_data} =
        auth_query_gql_by(:askme_bot, user,
          variables: %{
            "input" => %{
              "query" => "What is Glific?",
              "pageUrl" => "https://glific.org"
            }
          }
        )

      result = get_in(query_data, [:data, "askGlific"])
      assert result["answer"] == "Glific is great!"
      assert result["conversationId"] == "conv-gql-123"
      assert result["conversationName"] == "About Glific"
      assert result["errors"] == nil
    end

    test "returns error on API failure", %{staff: user} do
      Req.Test.stub(self(), fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"code" => "invalid", "message" => "Bad request"})
      end)

      {:ok, query_data} =
        auth_query_gql_by(:askme_bot, user,
          variables: %{
            "input" => %{
              "query" => "What is Glific?"
            }
          }
        )

      assert query_data.errors != nil
    end

    test "does not return conversation_name for follow-up messages", %{staff: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, %{
          "answer" => "More details here.",
          "conversation_id" => "conv-gql-123"
        })
      end)

      {:ok, query_data} =
        auth_query_gql_by(:askme_bot, user,
          variables: %{
            "input" => %{
              "query" => "Tell me more",
              "conversationId" => "conv-gql-123"
            }
          }
        )

      result = get_in(query_data, [:data, "askGlific"])
      assert result["answer"] == "More details here."
      assert result["conversationName"] == nil
    end
  end

  describe "askme_bot_conversations query" do
    test "returns conversations from Dify", %{staff: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, %{
          "data" => [
            %{
              "id" => "conv-gql-abc",
              "name" => "Glific Chat",
              "status" => "normal",
              "created_at" => 1_700_000_000,
              "updated_at" => 1_700_001_000
            }
          ],
          "has_more" => false,
          "limit" => 20
        })
      end)

      {:ok, query_data} =
        auth_query_gql_by(:conversations, user, variables: %{"limit" => 20})

      result = get_in(query_data, [:data, "askmeBotConversations"])
      assert length(result["conversations"]) == 1
      assert hd(result["conversations"])["id"] == "conv-gql-abc"
      assert hd(result["conversations"])["name"] == "Glific Chat"
      assert result["hasMore"] == false
    end

    test "returns empty list when Dify has no conversations", %{staff: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, %{
          "data" => [],
          "has_more" => false,
          "limit" => 20
        })
      end)

      {:ok, query_data} =
        auth_query_gql_by(:conversations, user, variables: %{})

      result = get_in(query_data, [:data, "askmeBotConversations"])
      assert result["conversations"] == []
    end

    test "returns error on Dify failure", %{staff: user} do
      Req.Test.stub(self(), fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "Server error"})
      end)

      {:ok, query_data} =
        auth_query_gql_by(:conversations, user, variables: %{})

      assert query_data.errors != nil
    end
  end

  describe "askme_bot_messages query" do
    test "returns messages for an owned conversation", %{staff: user} do
      insert_conversation("conv-msg-123", user)

      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, %{
          "data" => [
            %{
              "id" => "msg-001",
              "conversation_id" => "conv-msg-123",
              "query" => "What is Glific?",
              "answer" => "A communication platform.",
              "created_at" => 1_700_000_100
            }
          ],
          "has_more" => true,
          "limit" => 50
        })
      end)

      {:ok, query_data} =
        auth_query_gql_by(:messages, user,
          variables: %{"conversationId" => "conv-msg-123", "limit" => 50}
        )

      result = get_in(query_data, [:data, "askGlificMessages"])
      messages = result["messages"]
      assert length(messages) == 1
      assert hd(messages)["id"] == "msg-001"
      assert hd(messages)["query"] == "What is Glific?"
      assert hd(messages)["answer"] == "A communication platform."
      assert result["hasMore"] == true
    end

    test "returns error for conversation not owned by user", %{staff: user} do
      # Don't insert any conversation for this user

      {:ok, query_data} =
        auth_query_gql_by(:messages, user, variables: %{"conversationId" => "conv-not-owned"})

      assert query_data.errors != nil
    end

    test "supports pagination with firstId", %{staff: user} do
      insert_conversation("conv-msg-123", user)

      Req.Test.stub(self(), fn conn ->
        params = conn.params
        assert params["first_id"] == "msg-050"

        Req.Test.json(conn, %{
          "data" => [],
          "has_more" => false,
          "limit" => 50
        })
      end)

      {:ok, query_data} =
        auth_query_gql_by(:messages, user,
          variables: %{
            "conversationId" => "conv-msg-123",
            "limit" => 50,
            "firstId" => "msg-050"
          }
        )

      result = get_in(query_data, [:data, "askGlificMessages"])
      assert result["messages"] == []
      assert result["hasMore"] == false
    end
  end

  describe "askme_bot_feedback mutation" do
    test "submits like feedback successfully", %{staff: user} do
      Req.Test.stub(self(), fn conn ->
        assert conn.request_path == "/v1/messages/msg-gql-001/feedbacks"
        Req.Test.json(conn, %{"result" => "success"})
      end)

      {:ok, query_data} =
        auth_query_gql_by(:feedback, user,
          variables: %{
            "input" => %{
              "messageId" => "msg-gql-001",
              "rating" => "like"
            }
          }
        )

      result = get_in(query_data, [:data, "askGlificFeedback"])
      assert result["success"] == true
    end

    test "submits dislike feedback with content", %{staff: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, %{"result" => "success"})
      end)

      {:ok, query_data} =
        auth_query_gql_by(:feedback, user,
          variables: %{
            "input" => %{
              "messageId" => "msg-gql-002",
              "rating" => "dislike",
              "content" => "Not helpful"
            }
          }
        )

      result = get_in(query_data, [:data, "askGlificFeedback"])
      assert result["success"] == true
    end

    test "returns error on Dify failure", %{staff: user} do
      Req.Test.stub(self(), fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"error" => "Message not found"})
      end)

      {:ok, query_data} =
        auth_query_gql_by(:feedback, user,
          variables: %{
            "input" => %{
              "messageId" => "msg-nonexistent",
              "rating" => "like"
            }
          }
        )

      assert query_data.errors != nil
    end
  end
end
