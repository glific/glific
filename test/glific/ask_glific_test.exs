defmodule Glific.AskGlificTest do
  @moduledoc false
  use Glific.DataCase, async: false
  use Oban.Testing, repo: Glific.Repo, prefix: "global"

  alias Glific.{
    AI.Conversation,
    AI.Message,
    AI.Model.Stub,
    AI.StepWorker,
    AskGlific,
    Fixtures,
    Repo
  }

  setup %{organization_id: organization_id} do
    start_supervised!(Stub)
    FunWithFlags.enable(:is_ask_glific_enabled, for_actor: %{organization_id: organization_id})

    user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["manager"]})

    %{user: user, organization_id: organization_id}
  end

  describe "ask/2" do
    test "creates a conversation with the ask_glific skill and a derived title, and enqueues a step",
         %{user: user} do
      assert {:ok, ack} = AskGlific.ask(%{query: "What is Glific?"}, user)

      assert ack.answer == nil
      assert ack.message_id == nil
      assert ack.conversation_id != nil
      assert ack.request_id != nil

      conversation = Repo.get!(Conversation, String.to_integer(ack.conversation_id))
      assert conversation.skill == "ask_glific"
      assert conversation.title == "What is Glific?"
      assert conversation.active_status == :queued
      assert conversation.active_request_id == ack.request_id
      assert conversation.user_id == user.id

      assert_enqueued(
        worker: StepWorker,
        args: %{"conversation_id" => conversation.id, "user_id" => user.id}
      )
    end

    test "continues an existing conversation under the same skill", %{
      user: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          user_id: user.id,
          skill: "ask_glific"
        })

      assert {:ok, ack} =
               AskGlific.ask(
                 %{query: "Tell me more", conversation_id: to_string(conversation.id)},
                 user
               )

      assert ack.conversation_id == to_string(conversation.id)
      assert Repo.get!(Conversation, conversation.id).active_status == :queued
    end

    test "refuses to continue a conversation owned by another user", %{
      user: user,
      organization_id: organization_id
    } do
      other_user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["manager"]})

      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          user_id: other_user.id,
          skill: "ask_glific"
        })

      assert {:error, :not_found} =
               AskGlific.ask(
                 %{query: "Tell me more", conversation_id: to_string(conversation.id)},
                 user
               )
    end

    test "refuses a conversation that already has a request in flight", %{
      user: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          user_id: user.id,
          skill: "ask_glific",
          active_status: :running
        })

      assert {:error, :busy} =
               AskGlific.ask(
                 %{query: "Tell me more", conversation_id: to_string(conversation.id)},
                 user
               )
    end

    test "refuses a conversation belonging to a different skill", %{
      user: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          user_id: user.id,
          skill: "template_utility_rewrite"
        })

      assert {:error, :skill_mismatch} =
               AskGlific.ask(
                 %{query: "Tell me more", conversation_id: to_string(conversation.id)},
                 user
               )
    end

    test "refuses when the feature flag is disabled for the organization", %{
      user: user,
      organization_id: organization_id
    } do
      FunWithFlags.disable(:is_ask_glific_enabled, for_actor: %{organization_id: organization_id})

      assert {:error, :feature_disabled} = AskGlific.ask(%{query: "What is Glific?"}, user)
    end

    test "refuses a staff user, since the underlying skill requires manager", %{
      organization_id: organization_id
    } do
      staff_user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["staff"]})

      assert {:error, :forbidden} = AskGlific.ask(%{query: "What is Glific?"}, staff_user)
    end

    # The client issues its own request id and drops every published event whose id does not
    # match it — the subscription topic is org+user wide, so a second tab's events arrive too.
    # Generating our own id instead leaves the UI stuck on "thinking…" forever while the answer
    # it is waiting for gets discarded on arrival. This is not theoretical; it shipped.
    test "adopts the client's request_id as the correlation key", %{user: user} do
      client_request_id = "client-issued-abc-123"

      assert {:ok, ack} =
               AskGlific.ask(%{query: "What is a flow?", request_id: client_request_id}, user)

      assert ack.request_id == client_request_id

      conversation = Repo.get!(Conversation, String.to_integer(ack.conversation_id))
      assert conversation.active_request_id == client_request_id
    end

    test "generates a request_id when the client does not supply one", %{user: user} do
      assert {:ok, ack} = AskGlific.ask(%{query: "What is a flow?"}, user)

      assert is_binary(ack.request_id)
      assert ack.request_id != ""
    end

    test "returns an error for a blank query", %{user: user} do
      assert {:error, "Query is required"} = AskGlific.ask(%{query: "   "}, user)
    end

    test "trips the rate limit after too many requests in the window", %{user: user} do
      Enum.each(1..20, fn _n ->
        assert {:ok, _ack} = AskGlific.ask(%{query: "hi"}, user)
      end)

      assert {:error, :rate_limited} = AskGlific.ask(%{query: "hi"}, user)
    end
  end

  describe "submit_feedback/2" do
    test "records feedback on the caller's own turn", %{
      user: user,
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

      assert {:ok, %{success: true}} =
               AskGlific.submit_feedback(
                 %{message_id: to_string(message.id), rating: "like"},
                 user
               )

      assert Repo.get!(Message, message.id).feedback == "like"
    end

    test "refuses feedback on another user's message without leaking that it exists", %{
      user: user,
      organization_id: organization_id
    } do
      other_user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["manager"]})

      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          user_id: other_user.id,
          skill: "ask_glific"
        })

      message =
        Fixtures.ai_message_fixture(%{conversation: conversation, seq: 2, role: :assistant})

      assert {:error, "Message not found."} =
               AskGlific.submit_feedback(
                 %{message_id: to_string(message.id), rating: "like"},
                 user
               )
    end
  end

  describe "get_conversations/2" do
    test "returns only the caller's ask_glific conversations, excluding other skills and users",
         %{user: user, organization_id: organization_id} do
      ask_glific_conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          user_id: user.id,
          skill: "ask_glific",
          title: "About opt-outs"
        })

      Fixtures.ai_conversation_fixture(%{
        organization_id: organization_id,
        user_id: user.id,
        skill: "template_utility_rewrite"
      })

      other_user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["manager"]})

      Fixtures.ai_conversation_fixture(%{
        organization_id: organization_id,
        user_id: other_user.id,
        skill: "ask_glific"
      })

      assert {:ok, result} = AskGlific.get_conversations(user)
      assert length(result.conversations) == 1

      conversation = hd(result.conversations)
      assert conversation.id == to_string(ask_glific_conversation.id)
      assert conversation.name == "About opt-outs"
      assert result.has_more == false
    end
  end

  describe "get_messages/3" do
    test "returns turns oldest-first with unix-second timestamps", %{
      user: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          user_id: user.id,
          skill: "ask_glific"
        })

      user_message =
        Fixtures.ai_message_fixture(%{
          conversation: conversation,
          seq: 1,
          role: :user,
          reqllm_message: ReqLLM.Context.user("What is Glific?")
        })

      answer_message =
        Fixtures.ai_message_fixture(%{
          conversation: conversation,
          seq: 2,
          role: :assistant,
          reqllm_message: ReqLLM.Context.assistant("A communication platform.")
        })

      assert {:ok, result} = AskGlific.get_messages(to_string(conversation.id), user)

      assert result.messages == [
               %{
                 id: to_string(answer_message.id),
                 conversation_id: to_string(conversation.id),
                 query: "What is Glific?",
                 answer: "A communication platform.",
                 created_at: DateTime.to_unix(user_message.inserted_at),
                 feedback: nil
               }
             ]

      assert result.has_more == false
      assert result.limit == 20
    end

    test "returns not found for a conversation belonging to a different skill", %{
      user: user,
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          user_id: user.id,
          skill: "template_utility_rewrite"
        })

      assert {:error, "Conversation not found"} =
               AskGlific.get_messages(to_string(conversation.id), user)
    end
  end
end
