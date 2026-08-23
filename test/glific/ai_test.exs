defmodule Glific.AITest do
  @moduledoc false
  use Glific.DataCase, async: false

  alias Glific.{
    AI,
    AI.Codec,
    AI.Conversation,
    AI.Message,
    Fixtures,
    Repo
  }

  alias ReqLLM.Context

  describe "changesets" do
    test "Conversation.changeset/2 with valid attributes", %{organization_id: organization_id} do
      user = Fixtures.user_fixture(%{organization_id: organization_id})

      attrs = %{
        skill: "chat",
        max_steps: 20,
        codec_version: Codec.version(),
        user_id: user.id,
        organization_id: organization_id
      }

      changeset = Conversation.changeset(%Conversation{}, attrs)
      assert changeset.valid?
    end

    test "Conversation.changeset/2 with missing required fields is invalid" do
      changeset = Conversation.changeset(%Conversation{}, %{})
      refute changeset.valid?

      assert %{
               skill: ["can't be blank"],
               max_steps: ["can't be blank"],
               codec_version: ["can't be blank"],
               user_id: ["can't be blank"],
               organization_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "Conversation.changeset/2 rejects a non-positive max_steps", %{
      organization_id: organization_id
    } do
      user = Fixtures.user_fixture(%{organization_id: organization_id})

      attrs = %{
        skill: "chat",
        max_steps: 0,
        codec_version: Codec.version(),
        user_id: user.id,
        organization_id: organization_id
      }

      changeset = Conversation.changeset(%Conversation{}, attrs)
      refute changeset.valid?
      assert %{max_steps: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "Message.changeset/2 with missing required fields is invalid" do
      changeset = Message.changeset(%Message{}, %{})
      refute changeset.valid?

      assert %{
               conversation_id: ["can't be blank"],
               seq: ["can't be blank"],
               role: ["can't be blank"],
               parts: ["can't be blank"],
               organization_id: ["can't be blank"]
             } = errors_on(changeset)
    end
  end

  describe "create_conversation/1" do
    test "creates a conversation with valid attrs", %{organization_id: organization_id} do
      user = Fixtures.user_fixture(%{organization_id: organization_id})

      assert {:ok, %Conversation{} = conversation} =
               AI.create_conversation(%{
                 skill: "chat",
                 max_steps: 20,
                 codec_version: Codec.version(),
                 user_id: user.id,
                 organization_id: organization_id
               })

      assert conversation.status == "active"
      assert conversation.step_count == 0
    end

    test "returns an error changeset for invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = AI.create_conversation(%{})
    end

    test "enforces active_request_id uniqueness", %{organization_id: organization_id} do
      user = Fixtures.user_fixture(%{organization_id: organization_id})

      base_attrs = %{
        skill: "chat",
        max_steps: 20,
        codec_version: Codec.version(),
        user_id: user.id,
        organization_id: organization_id,
        active_request_id: "shared-request-id"
      }

      assert {:ok, _first} = AI.create_conversation(base_attrs)
      assert {:error, changeset} = AI.create_conversation(base_attrs)
      assert %{active_request_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_conversation/2" do
    test "moves execution state as a run progresses", %{organization_id: organization_id} do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      assert {:ok, updated} =
               AI.update_conversation(conversation, %{
                 active_request_id: "req-1",
                 active_status: :running,
                 step_count: 1
               })

      assert updated.active_request_id == "req-1"
      assert updated.active_status == :running
      assert updated.step_count == 1
    end
  end

  describe "conversations are private to their creator" do
    test "get_conversation!/2 returns the conversation for its creator", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      assert %Conversation{id: id} =
               AI.get_conversation!(conversation.id, conversation.user_id)

      assert id == conversation.id
    end

    test "get_conversation!/2 raises for a different user in the same organization", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})
      other_user = Fixtures.user_fixture(%{organization_id: organization_id})

      assert_raise Ecto.NoResultsError, fn ->
        AI.get_conversation!(conversation.id, other_user.id)
      end
    end

    test "fetch_conversation/2 returns an error for a different user", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})
      other_user = Fixtures.user_fixture(%{organization_id: organization_id})

      assert {:error, _reason} = AI.fetch_conversation(conversation.id, other_user.id)
      assert {:ok, _conversation} = AI.fetch_conversation(conversation.id, conversation.user_id)
    end

    test "fetch_conversation/2 does not leak a conversation from another organization", %{
      organization_id: organization_id
    } do
      other_org = Fixtures.organization_fixture(%{shortcode: "ai_test_other_org"})
      other_user = Fixtures.user_fixture(%{organization_id: other_org.id})

      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: other_org.id,
          user_id: other_user.id
        })

      # Fixtures.organization_fixture/1 warms the cache for the org it creates, which leaves
      # the process's ambient organization id pointed at that org — restore it to prove the
      # scope is actually enforced, not merely left untouched.
      Repo.put_organization_id(organization_id)

      assert {:error, _reason} = AI.fetch_conversation(conversation.id, other_user.id)
    end
  end

  describe "list_conversations/1 and count_conversations/1" do
    test "requires filter.user_id", %{organization_id: organization_id} do
      Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      assert_raise ArgumentError, ~r/filter.user_id is required/, fn ->
        AI.list_conversations(%{filter: %{}})
      end

      assert_raise ArgumentError, ~r/filter.user_id is required/, fn ->
        AI.count_conversations(%{filter: %{}})
      end
    end

    test "scopes to the given user", %{organization_id: organization_id} do
      user = Fixtures.user_fixture(%{organization_id: organization_id})
      other_user = Fixtures.user_fixture(%{organization_id: organization_id})

      mine =
        Fixtures.ai_conversation_fixture(%{organization_id: organization_id, user_id: user.id})

      Fixtures.ai_conversation_fixture(%{
        organization_id: organization_id,
        user_id: other_user.id
      })

      results = AI.list_conversations(%{filter: %{user_id: user.id}})

      assert Enum.map(results, & &1.id) == [mine.id]
      assert AI.count_conversations(%{filter: %{user_id: user.id}}) == 1
    end

    test "orders the chat list by updated_at", %{organization_id: organization_id} do
      user = Fixtures.user_fixture(%{organization_id: organization_id})

      recently_active =
        Fixtures.ai_conversation_fixture(%{organization_id: organization_id, user_id: user.id})

      stale =
        Fixtures.ai_conversation_fixture(%{organization_id: organization_id, user_id: user.id})

      # `updated_at` has second-level precision and both rows are created within the same test,
      # so push `stale` visibly into the past instead of relying on wall-clock ordering.
      long_ago = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
      Repo.update_all(where(Conversation, id: ^stale.id), set: [updated_at: long_ago])

      results = AI.list_conversations(%{filter: %{user_id: user.id}, opts: %{order: :desc}})

      assert Enum.map(results, & &1.id) == [recently_active.id, stale.id]
    end
  end

  describe "append_message/2" do
    test "inserts a message at the given seq", %{organization_id: organization_id} do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})
      {:ok, parts} = Codec.encode(Context.user("hello"))

      assert {:ok, :inserted} =
               AI.append_message(conversation, %{seq: 1, role: :user, parts: parts})

      assert [%Message{seq: 1, role: :user}] =
               Message |> where(conversation_id: ^conversation.id) |> Repo.all()
    end

    test "a retried step at the same seq is a no-op, not a duplicate", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})
      {:ok, parts} = Codec.encode(Context.user("hello"))
      attrs = %{seq: 1, role: :user, parts: parts}

      assert {:ok, :inserted} = AI.append_message(conversation, attrs)
      assert {:ok, :already_present} = AI.append_message(conversation, attrs)

      assert 1 ==
               Message
               |> where(conversation_id: ^conversation.id)
               |> Repo.aggregate(:count)
    end

    test "returns an error changeset for invalid attrs", %{organization_id: organization_id} do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      assert {:error, %Ecto.Changeset{}} = AI.append_message(conversation, %{seq: 1})
    end
  end

  describe "build_context/1" do
    test "decodes complete rows in seq order, skipping failed rows", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 1,
        reqllm_message: Context.user("first")
      })

      {:ok, failed_parts} = Codec.encode(Context.assistant("should be skipped"))

      %Message{}
      |> Message.changeset(%{
        conversation_id: conversation.id,
        seq: 2,
        role: :assistant,
        parts: failed_parts,
        status: :failed,
        organization_id: organization_id
      })
      |> Repo.insert!()

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 3,
        role: :assistant,
        reqllm_message: Context.assistant("third")
      })

      assert {:ok, %Context{messages: messages}} = AI.build_context(conversation.id)

      texts =
        messages
        |> Enum.flat_map(& &1.content)
        |> Enum.map(& &1.text)

      assert texts == ["first", "third"]
    end

    test "returns an empty context when there are no messages", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      assert {:ok, %Context{messages: []}} = AI.build_context(conversation.id)
    end

    test "surfaces a decode failure instead of silently dropping the row", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      %Message{}
      |> Message.changeset(%{
        conversation_id: conversation.id,
        seq: 1,
        role: :user,
        parts: %{"no_version_key" => true},
        status: :complete,
        organization_id: organization_id
      })
      |> Repo.insert!()

      assert {:error, _reason} = AI.build_context(conversation.id)
    end
  end

  describe "list_messages/2" do
    test "orders messages by seq ascending regardless of insertion order", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      Fixtures.ai_message_fixture(%{conversation: conversation, seq: 3})
      Fixtures.ai_message_fixture(%{conversation: conversation, seq: 1})
      Fixtures.ai_message_fixture(%{conversation: conversation, seq: 2})

      assert [%Message{seq: 1}, %Message{seq: 2}, %Message{seq: 3}] =
               AI.list_messages(conversation.id)
    end

    test "scopes to the given conversation_id only", %{organization_id: organization_id} do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})
      other_conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      Fixtures.ai_message_fixture(%{conversation: conversation, seq: 1})
      Fixtures.ai_message_fixture(%{conversation: other_conversation, seq: 1})

      assert [%Message{conversation_id: id}] = AI.list_messages(conversation.id)
      assert id == conversation.id
    end

    test "applies limit/offset from opts", %{organization_id: organization_id} do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      Fixtures.ai_message_fixture(%{conversation: conversation, seq: 1})
      Fixtures.ai_message_fixture(%{conversation: conversation, seq: 2})
      Fixtures.ai_message_fixture(%{conversation: conversation, seq: 3})

      assert [%Message{seq: 2}] =
               AI.list_messages(conversation.id, %{opts: %{limit: 1, offset: 1}})
    end

    test "returns an empty list when the conversation has no messages", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      assert [] == AI.list_messages(conversation.id)
    end
  end

  describe "list_turns/2 and count_turns/1" do
    test "pairs a simple user/assistant exchange into one turn", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 1,
        role: :user,
        reqllm_message: Context.user("What is Glific?")
      })

      answer =
        Fixtures.ai_message_fixture(%{
          conversation: conversation,
          seq: 2,
          role: :assistant,
          reqllm_message: Context.assistant("Glific is a WhatsApp platform.")
        })

      assert [turn] = AI.list_turns(conversation.id)
      assert turn.id == to_string(answer.id)
      assert turn.conversation_id == to_string(conversation.id)
      assert turn.query == "What is Glific?"
      assert turn.answer == "Glific is a WhatsApp platform."
      assert turn.feedback == nil
      assert AI.count_turns(conversation.id) == 1
    end

    test "a multi-step run collapses to one turn, tool rows never surface, and the answer is the final assistant row",
         %{organization_id: organization_id} do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 1,
        role: :user,
        reqllm_message: Context.user("weather in SF?")
      })

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 2,
        role: :assistant,
        reqllm_message: Context.assistant("", tool_calls: [{"get_weather", %{location: "SF"}}])
      })

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 3,
        role: :tool,
        reqllm_message: Context.tool_result("call_1", "62F and sunny")
      })

      final =
        Fixtures.ai_message_fixture(%{
          conversation: conversation,
          seq: 4,
          role: :assistant,
          reqllm_message: Context.assistant("It's 62F and sunny in SF.")
        })

      assert [turn] = AI.list_turns(conversation.id)
      assert turn.id == to_string(final.id)
      assert turn.query == "weather in SF?"
      assert turn.answer == "It's 62F and sunny in SF."
      assert AI.count_turns(conversation.id) == 1
    end

    test "drops a trailing user row that has no assistant reply yet", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 1,
        role: :user,
        reqllm_message: Context.user("first")
      })

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 2,
        role: :assistant,
        reqllm_message: Context.assistant("first answer")
      })

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 3,
        role: :user,
        reqllm_message: Context.user("still waiting on a reply")
      })

      assert [turn] = AI.list_turns(conversation.id)
      assert turn.query == "first"
      assert AI.count_turns(conversation.id) == 1
    end

    test "orders turns oldest-first regardless of insertion order", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 4,
        role: :assistant,
        reqllm_message: Context.assistant("a2")
      })

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 1,
        role: :user,
        reqllm_message: Context.user("q1")
      })

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 3,
        role: :user,
        reqllm_message: Context.user("q2")
      })

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 2,
        role: :assistant,
        reqllm_message: Context.assistant("a1")
      })

      assert [%{query: "q1"}, %{query: "q2"}] = AI.list_turns(conversation.id)
    end

    test "limit and first_id paginate backwards, still oldest-first", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      for index <- 1..3 do
        Fixtures.ai_message_fixture(%{
          conversation: conversation,
          seq: index * 2 - 1,
          role: :user,
          reqllm_message: Context.user("q#{index}")
        })

        Fixtures.ai_message_fixture(%{
          conversation: conversation,
          seq: index * 2,
          role: :assistant,
          reqllm_message: Context.assistant("a#{index}")
        })
      end

      assert [_turn1, _turn2, turn3] = all_turns = AI.list_turns(conversation.id)
      assert Enum.map(all_turns, & &1.query) == ["q1", "q2", "q3"]

      assert [%{query: "q2"}] =
               AI.list_turns(conversation.id, %{limit: 1, first_id: turn3.id})

      assert Enum.map(
               AI.list_turns(conversation.id, %{limit: 10, first_id: turn3.id}),
               & &1.query
             ) == ["q1", "q2"]

      assert [%{query: "q3"}] = AI.list_turns(conversation.id, %{limit: 1})
    end

    test "an unparseable first_id is treated as absent rather than raising", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 1,
        role: :user,
        reqllm_message: Context.user("q1")
      })

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 2,
        role: :assistant,
        reqllm_message: Context.assistant("a1")
      })

      assert [%{query: "q1"}] = AI.list_turns(conversation.id, %{first_id: "not-a-number"})
    end

    test "excludes failed rows from turns", %{organization_id: organization_id} do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 1,
        role: :user,
        reqllm_message: Context.user("hello")
      })

      {:ok, failed_parts} = Codec.encode(Context.assistant("should not appear"))

      %Message{}
      |> Message.changeset(%{
        conversation_id: conversation.id,
        seq: 2,
        role: :assistant,
        parts: failed_parts,
        status: :failed,
        organization_id: organization_id
      })
      |> Repo.insert!()

      assert AI.list_turns(conversation.id) == []
      assert AI.count_turns(conversation.id) == 0
    end
  end

  describe "set_feedback/3" do
    test "records a like on the answer", %{organization_id: organization_id} do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      message =
        Fixtures.ai_message_fixture(%{conversation: conversation, seq: 1, role: :assistant})

      assert {:ok, updated} = AI.set_feedback(to_string(message.id), conversation.user_id, "like")
      assert updated.feedback == "like"
    end

    test "records a dislike on the answer", %{organization_id: organization_id} do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      message =
        Fixtures.ai_message_fixture(%{conversation: conversation, seq: 1, role: :assistant})

      assert {:ok, updated} =
               AI.set_feedback(to_string(message.id), conversation.user_id, "dislike")

      assert updated.feedback == "dislike"
    end

    test "another user's message returns :not_found, without leaking that it exists", %{
      organization_id: organization_id
    } do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      message =
        Fixtures.ai_message_fixture(%{conversation: conversation, seq: 1, role: :assistant})

      other_user = Fixtures.user_fixture(%{organization_id: organization_id})

      assert {:error, :not_found} = AI.set_feedback(to_string(message.id), other_user.id, "like")
    end

    test "a non-existent message id returns :not_found", %{organization_id: organization_id} do
      user = Fixtures.user_fixture(%{organization_id: organization_id})

      assert {:error, :not_found} = AI.set_feedback("999999999", user.id, "like")
    end

    test "a non-numeric message id returns :not_found instead of raising", %{
      organization_id: organization_id
    } do
      user = Fixtures.user_fixture(%{organization_id: organization_id})

      assert {:error, :not_found} = AI.set_feedback("not-a-number", user.id, "like")
    end

    test "an invalid rating is rejected", %{organization_id: organization_id} do
      conversation = Fixtures.ai_conversation_fixture(%{organization_id: organization_id})

      message =
        Fixtures.ai_message_fixture(%{conversation: conversation, seq: 1, role: :assistant})

      assert {:error, :invalid_rating} =
               AI.set_feedback(to_string(message.id), conversation.user_id, "love-it")
    end
  end

  describe "derive_title/1" do
    test "returns short input untouched" do
      assert AI.derive_title("Hello there") == "Hello there"
    end

    test "returns empty input untouched" do
      assert AI.derive_title("") == ""
    end

    test "truncates long input on a word boundary with a trailing ellipsis" do
      text =
        "How do I configure a WhatsApp flow that greets a new contact and then routes " <>
          "them to a human agent for a warm handoff"

      title = AI.derive_title(text)

      assert String.ends_with?(title, "…")
      assert String.length(title) <= 61
      assert String.starts_with?(text, String.trim_trailing(title, "…"))
      refute title == text
    end
  end
end
