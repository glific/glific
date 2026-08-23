defmodule GlificWeb.Resolvers.AskGlificTest do
  @moduledoc """
  GraphQL integration tests for the Ask Glific surface, now backed by the in-Glific AI agent
  runtime instead of Dify. `askGlific` is fire-and-forget: it acks synchronously and the real
  answer is published later on the `askGlificResponse` subscription (bridged from the runtime's
  `ai_request_event` topic by `Glific.AskGlific.Bridge`) — that publish path is covered at the
  unit level in `test/glific/ai/publisher_test.exs`, not re-tested here.
  """
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{AI.Conversation, AI.Model.Stub, Fixtures, Repo}

  load_gql(:ask_glific, GlificWeb.Schema, "assets/gql/ask_glific/ask.gql")
  load_gql(:conversations, GlificWeb.Schema, "assets/gql/ask_glific/conversations.gql")
  load_gql(:messages, GlificWeb.Schema, "assets/gql/ask_glific/messages.gql")
  load_gql(:feedback, GlificWeb.Schema, "assets/gql/ask_glific/feedback.gql")

  setup %{organization_id: organization_id} do
    start_supervised!(Stub)
    FunWithFlags.enable(:is_ask_glific_enabled, for_actor: %{organization_id: organization_id})
    :ok
  end

  describe "ask_glific mutation" do
    test "a manager starts a run and gets an immediate placeholder ack", %{manager: user} do
      {:ok, query_data} =
        auth_query_gql_by(:ask_glific, user,
          variables: %{
            "input" => %{"query" => "What is Glific?", "pageUrl" => "https://glific.org"}
          }
        )

      result = get_in(query_data, [:data, "askGlific"])
      assert result["answer"] == nil
      assert result["conversationId"] != nil
      assert result["requestId"] != nil
      assert result["errors"] in [nil, []]

      conversation = Repo.get!(Conversation, result["conversationId"])
      assert conversation.skill == "ask_glific"
      assert conversation.title == "What is Glific?"
    end

    test "continuing an existing conversation succeeds", %{
      manager: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          user_id: user.id,
          skill: "ask_glific"
        })

      {:ok, query_data} =
        auth_query_gql_by(:ask_glific, user,
          variables: %{
            "input" => %{
              "query" => "Tell me more",
              "conversationId" => to_string(conversation.id)
            }
          }
        )

      result = get_in(query_data, [:data, "askGlific"])
      assert result["conversationId"] == to_string(conversation.id)
      assert result["errors"] in [nil, []]
    end

    test "a staff user is rejected, since the underlying skill requires manager", %{staff: user} do
      {:ok, query_data} =
        auth_query_gql_by(:ask_glific, user, variables: %{"input" => %{"query" => "Hi"}})

      result = get_in(query_data, [:data, "askGlific"])
      assert result["answer"] == nil
      assert result["conversationId"] == nil
      assert [%{"message" => message} | _] = result["errors"]
      assert message =~ "permission"
    end

    test "is rejected when the feature flag is disabled for the organization", %{
      manager: user,
      organization_id: organization_id
    } do
      FunWithFlags.disable(:is_ask_glific_enabled, for_actor: %{organization_id: organization_id})

      {:ok, query_data} =
        auth_query_gql_by(:ask_glific, user, variables: %{"input" => %{"query" => "Hi"}})

      result = get_in(query_data, [:data, "askGlific"])
      assert result["conversationId"] == nil
      assert [%{"message" => message} | _] = result["errors"]
      assert message =~ "not enabled"
    end
  end

  describe "ask_glific_conversations query" do
    test "returns only the caller's ask_glific conversations", %{
      manager: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          user_id: user.id,
          skill: "ask_glific",
          title: "Glific Chat"
        })

      Fixtures.ai_conversation_fixture(%{
        organization_id: organization_id,
        user_id: user.id,
        skill: "template_utility_rewrite"
      })

      {:ok, query_data} = auth_query_gql_by(:conversations, user, variables: %{"limit" => 20})

      result = get_in(query_data, [:data, "askGlificConversations"])
      assert length(result["conversations"]) == 1
      assert hd(result["conversations"])["id"] == to_string(conversation.id)
      assert hd(result["conversations"])["name"] == "Glific Chat"
      assert result["hasMore"] == false
    end

    test "returns an empty list when the caller has no ask_glific conversations", %{
      manager: user
    } do
      {:ok, query_data} = auth_query_gql_by(:conversations, user, variables: %{})

      result = get_in(query_data, [:data, "askGlificConversations"])
      assert result["conversations"] == []
    end
  end

  describe "ask_glific_messages query" do
    test "returns turn history for an owned conversation", %{
      manager: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          user_id: user.id,
          skill: "ask_glific"
        })

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 1,
        role: :user,
        reqllm_message: ReqLLM.Context.user("What is Glific?")
      })

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 2,
        role: :assistant,
        reqllm_message: ReqLLM.Context.assistant("A communication platform.")
      })

      {:ok, query_data} =
        auth_query_gql_by(:messages, user,
          variables: %{"conversationId" => to_string(conversation.id), "limit" => 50}
        )

      result = get_in(query_data, [:data, "askGlificMessages"])
      messages = result["messages"]
      assert length(messages) == 1
      assert hd(messages)["query"] == "What is Glific?"
      assert hd(messages)["answer"] == "A communication platform."
      assert result["hasMore"] == false
    end

    test "returns an error for a conversation not owned by the caller", %{
      manager: user,
      organization_id: organization_id
    } do
      other_user =
        Fixtures.user_fixture(%{organization_id: organization_id, roles: ["manager"]})

      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          user_id: other_user.id,
          skill: "ask_glific"
        })

      {:ok, query_data} =
        auth_query_gql_by(:messages, user,
          variables: %{"conversationId" => to_string(conversation.id)}
        )

      assert query_data.errors != nil
    end
  end

  describe "ask_glific_feedback mutation" do
    test "submits like feedback successfully", %{
      manager: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          user_id: user.id,
          skill: "ask_glific"
        })

      message =
        Fixtures.ai_message_fixture(%{conversation: conversation, seq: 2, role: :assistant})

      {:ok, query_data} =
        auth_query_gql_by(:feedback, user,
          variables: %{
            "input" => %{"messageId" => to_string(message.id), "rating" => "like"}
          }
        )

      result = get_in(query_data, [:data, "askGlificFeedback"])
      assert result["success"] == true
    end

    test "returns an error for a message that does not belong to the caller", %{manager: user} do
      {:ok, query_data} =
        auth_query_gql_by(:feedback, user,
          variables: %{"input" => %{"messageId" => "999999999", "rating" => "like"}}
        )

      assert query_data.errors != nil
    end
  end
end
