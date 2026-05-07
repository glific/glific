defmodule Glific.AskGlificTest do
  use Glific.DataCase

  alias Glific.AskGlific
  alias Glific.AskGlific.Conversation
  alias Glific.Repo

  @dify_success_response %{
    "answer" => "Glific is a two-way communication platform.",
    "conversation_id" => "conv-abc-123"
  }

  @dify_name_response %{
    "name" => "What is Glific"
  }

  @dify_conversations_response %{
    "data" => [
      %{
        "id" => "conv-abc-123",
        "name" => "What is Glific",
        "status" => "normal",
        "created_at" => 1_700_000_000,
        "updated_at" => 1_700_001_000
      },
      %{
        "id" => "conv-def-456",
        "name" => "Flow setup",
        "status" => "normal",
        "created_at" => 1_700_002_000,
        "updated_at" => 1_700_003_000
      }
    ],
    "has_more" => false,
    "limit" => 20
  }

  @dify_messages_response %{
    "data" => [
      %{
        "id" => "msg-001",
        "conversation_id" => "conv-abc-123",
        "query" => "What is Glific?",
        "answer" => "Glific is a two-way communication platform.",
        "created_at" => 1_700_000_100
      },
      %{
        "id" => "msg-002",
        "conversation_id" => "conv-abc-123",
        "query" => "Tell me more",
        "answer" => "It supports WhatsApp integration.",
        "created_at" => 1_700_000_200
      }
    ],
    "has_more" => false,
    "limit" => 20
  }

  setup do
    test_pid = self()

    Application.put_env(:glific, :dify_req_plug, {Req.Test, test_pid})
    Application.put_env(:glific, :dify_api_key, "test-api-key")

    on_exit(fn ->
      Application.delete_env(:glific, :dify_req_plug)
      Application.delete_env(:glific, :dify_api_key)
    end)

    user =
      Glific.Fixtures.user_fixture(%{
        name: "AskGlific Test User",
        roles: ["staff"]
      })

    %{user: user}
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

  describe "ask/2" do
    test "returns answer and conversation_id on success", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, @dify_success_response)
      end)

      params = %{query: "What is Glific?", page_url: "https://glific.org"}

      assert {:ok, result} = AskGlific.ask(params, user)
      assert result.answer == "Glific is a two-way communication platform."
      assert result.conversation_id == "conv-abc-123"
    end

    test "returns conversation_name for new conversations", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        case conn.request_path do
          "/v1/chat-messages" ->
            Req.Test.json(conn, @dify_success_response)

          "/v1/conversations/conv-abc-123/name" ->
            Req.Test.json(conn, @dify_name_response)
        end
      end)

      params = %{query: "What is Glific?"}

      assert {:ok, result} = AskGlific.ask(params, user)
      assert result.conversation_name == "What is Glific"
    end

    test "does not generate name for follow-up messages", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, @dify_success_response)
      end)

      params = %{query: "Tell me more", conversation_id: "conv-abc-123"}

      assert {:ok, result} = AskGlific.ask(params, user)
      assert result.conversation_name == nil
    end

    test "saves conversation to database on success", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, @dify_success_response)
      end)

      params = %{query: "What is Glific?"}

      assert {:ok, _result} = AskGlific.ask(params, user)

      conversation = Repo.get_by(Conversation, conversation_id: "conv-abc-123")
      assert conversation != nil
      assert conversation.user_id == user.id
      assert conversation.organization_id == user.organization_id
    end

    test "does not duplicate conversation on follow-up messages", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, @dify_success_response)
      end)

      params = %{query: "What is Glific?"}
      assert {:ok, _} = AskGlific.ask(params, user)

      # Second message in same conversation
      params2 = %{query: "Tell me more", conversation_id: "conv-abc-123"}
      assert {:ok, _} = AskGlific.ask(params2, user)

      conversations =
        Conversation
        |> where([c], c.conversation_id == "conv-abc-123" and c.user_id == ^user.id)
        |> Repo.all()

      assert length(conversations) == 1
    end

    test "returns error on API failure", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"code" => "invalid_param", "message" => "Bad request"})
      end)

      params = %{query: "What is Glific?"}

      assert {:error, error} = AskGlific.ask(params, user)
      assert error =~ "Dify API error"
    end

    test "handles missing answer gracefully", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, %{"conversation_id" => "conv-abc-123"})
      end)

      params = %{query: "What is Glific?"}

      assert {:ok, result} = AskGlific.ask(params, user)
      assert result.answer == ""
    end

    test "handles missing conversation_id in response", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, %{"answer" => "Hello"})
      end)

      params = %{query: "Hi"}

      assert {:ok, result} = AskGlific.ask(params, user)
      assert result.conversation_id == ""
    end

    test "returns nil conversation_name when name generation fails", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        case conn.request_path do
          "/v1/chat-messages" ->
            Req.Test.json(conn, @dify_success_response)

          "/v1/conversations/conv-abc-123/name" ->
            conn
            |> Plug.Conn.put_status(500)
            |> Req.Test.json(%{"error" => "Internal error"})
        end
      end)

      params = %{query: "What is Glific?"}

      assert {:ok, result} = AskGlific.ask(params, user)
      assert result.conversation_name == nil
    end
  end

  describe "get_conversations/2" do
    test "returns conversations tracked in DB for the user", %{user: user} do
      insert_conversation("conv-abc-123", user)
      insert_conversation("conv-def-456", user)

      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, @dify_conversations_response)
      end)

      assert {:ok, result} = AskGlific.get_conversations(user)
      assert length(result.conversations) == 2
      assert hd(result.conversations).id == "conv-abc-123"
      assert hd(result.conversations).name == "What is Glific"
    end

    test "returns parsed conversation fields", %{user: user} do
      insert_conversation("conv-abc-123", user)
      insert_conversation("conv-def-456", user)

      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, @dify_conversations_response)
      end)

      assert {:ok, result} = AskGlific.get_conversations(user)
      conv = hd(result.conversations)
      assert conv.status == "normal"
      assert conv.created_at == 1_700_000_000
      assert conv.updated_at == 1_700_001_000
    end

    test "returns has_more and limit from Dify response", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, @dify_conversations_response)
      end)

      assert {:ok, result} = AskGlific.get_conversations(user)
      assert result.has_more == false
      assert result.limit == 20
    end

    test "returns empty list when Dify has no conversations", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, %{"data" => [], "has_more" => false, "limit" => 20})
      end)

      assert {:ok, result} = AskGlific.get_conversations(user)
      assert result.conversations == []
    end

    test "passes limit and last_id params to Dify", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        params = conn.params
        assert params["limit"] == "5"
        assert params["last_id"] == "conv-xyz"
        Req.Test.json(conn, %{"data" => [], "has_more" => false, "limit" => 5})
      end)

      assert {:ok, _result} =
               AskGlific.get_conversations(user, %{limit: 5, last_id: "conv-xyz"})
    end

    test "sends correct user identifier to Dify", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        params = conn.params
        assert params["user"] == "org-#{user.organization_id}-user-#{user.id}"
        Req.Test.json(conn, %{"data" => [], "has_more" => false, "limit" => 20})
      end)

      assert {:ok, _result} = AskGlific.get_conversations(user)
    end

    test "returns error on Dify API failure", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "Server error"})
      end)

      assert {:error, error} = AskGlific.get_conversations(user)
      assert error =~ "Dify API error"
    end
  end

  describe "get_messages/3" do
    test "returns messages for an owned conversation", %{user: user} do
      insert_conversation("conv-abc-123", user)

      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, @dify_messages_response)
      end)

      assert {:ok, result} = AskGlific.get_messages("conv-abc-123", user)
      assert length(result.messages) == 2

      first = hd(result.messages)
      assert first.id == "msg-001"
      assert first.query == "What is Glific?"
      assert first.answer == "Glific is a two-way communication platform."
      assert first.conversation_id == "conv-abc-123"
      assert first.created_at == 1_700_000_100
    end

    test "returns error for conversation not owned by user", %{user: user} do
      other_user =
        Glific.Fixtures.user_fixture(%{
          name: "Other User",
          roles: ["staff"]
        })

      insert_conversation("conv-abc-123", other_user)

      assert {:error, "Conversation not found"} =
               AskGlific.get_messages("conv-abc-123", user)
    end

    test "returns error for non-existent conversation", %{user: user} do
      assert {:error, "Conversation not found"} =
               AskGlific.get_messages("non-existent", user)
    end

    test "returns has_more and limit from Dify response", %{user: user} do
      insert_conversation("conv-abc-123", user)

      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, @dify_messages_response)
      end)

      assert {:ok, result} = AskGlific.get_messages("conv-abc-123", user)
      assert result.has_more == false
      assert result.limit == 20
    end

    test "passes limit and first_id params to Dify", %{user: user} do
      insert_conversation("conv-abc-123", user)

      Req.Test.stub(self(), fn conn ->
        params = conn.params
        assert params["limit"] == "10"
        assert params["first_id"] == "msg-050"
        Req.Test.json(conn, %{"data" => [], "has_more" => false, "limit" => 10})
      end)

      assert {:ok, _result} =
               AskGlific.get_messages("conv-abc-123", user, %{limit: 10, first_id: "msg-050"})
    end

    test "returns error on Dify API failure", %{user: user} do
      insert_conversation("conv-abc-123", user)

      Req.Test.stub(self(), fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "Server error"})
      end)

      assert {:error, error} = AskGlific.get_messages("conv-abc-123", user)
      assert error =~ "Dify API error"
    end

    test "handles empty message list", %{user: user} do
      insert_conversation("conv-abc-123", user)

      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, %{"data" => [], "has_more" => false, "limit" => 20})
      end)

      assert {:ok, result} = AskGlific.get_messages("conv-abc-123", user)
      assert result.messages == []
    end

    test "returns message_id in ask response", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, %{
          "answer" => "Hello!",
          "conversation_id" => "conv-abc-123",
          "message_id" => "msg-feedback-001"
        })
      end)

      params = %{query: "What is Glific?", conversation_id: "conv-abc-123"}

      assert {:ok, result} = AskGlific.ask(params, user)
      assert result.message_id == "msg-feedback-001"
    end

    test "handles messages with has_more true for pagination", %{user: user} do
      insert_conversation("conv-abc-123", user)

      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, %{
          "data" => [
            %{
              "id" => "msg-001",
              "conversation_id" => "conv-abc-123",
              "query" => "Q1",
              "answer" => "A1",
              "created_at" => 1_700_000_100
            }
          ],
          "has_more" => true,
          "limit" => 1
        })
      end)

      assert {:ok, result} = AskGlific.get_messages("conv-abc-123", user)
      assert length(result.messages) == 1
      assert result.has_more == true
    end
  end

  describe "submit_feedback/2" do
    test "submits like feedback successfully", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/messages/msg-feedback-001/feedbacks"

        Req.Test.json(conn, %{"result" => "success"})
      end)

      params = %{message_id: "msg-feedback-001", rating: "like"}

      assert {:ok, result} = AskGlific.submit_feedback(params, user)
      assert result.success == true
    end

    test "submits dislike feedback successfully", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        Req.Test.json(conn, %{"result" => "success"})
      end)

      params = %{message_id: "msg-feedback-002", rating: "dislike", content: "Not helpful"}

      assert {:ok, result} = AskGlific.submit_feedback(params, user)
      assert result.success == true
    end

    test "returns error on Dify API failure", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"error" => "Message not found"})
      end)

      params = %{message_id: "msg-nonexistent", rating: "like"}

      assert {:error, error} = AskGlific.submit_feedback(params, user)
      assert error =~ "Dify API error"
    end

    test "sends correct user identifier and rating to Dify", %{user: user} do
      Req.Test.stub(self(), fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        parsed = Jason.decode!(body)
        assert parsed["user"] == "org-#{user.organization_id}-user-#{user.id}"
        assert parsed["rating"] == "like"
        assert parsed["content"] == "Great answer!"

        Req.Test.json(conn, %{"result" => "success"})
      end)

      params = %{message_id: "msg-001", rating: "like", content: "Great answer!"}

      assert {:ok, _result} = AskGlific.submit_feedback(params, user)
    end
  end
end
