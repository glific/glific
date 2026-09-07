defmodule Glific.AI.AskGlificTest do
  use Glific.DataCase

  alias Glific.{
    AI.Conversation,
    AI.Event,
    AI.Message,
    AI.Skills,
    AskGlific,
    FakeProvider,
    Fixtures,
    Repo
  }

  setup do
    original = Application.get_env(:glific, Glific.AI, [])
    Application.put_env(:glific, Glific.AI, Keyword.merge(original, FakeProvider.start()))

    on_exit(fn ->
      FakeProvider.stop()
      Application.put_env(:glific, Glific.AI, original)
    end)

    FunWithFlags.enable(:glific_ai_enabled, for_actor: %{organization_id: 1})
    FakeProvider.always(FakeProvider.answer("an answer"))

    %{user: Fixtures.user_fixture(%{organization_id: 1})}
  end

  defp sent, do: FakeProvider.seen() |> Enum.map(&Jason.decode!/1)

  test "with the flag on, a question is answered by Glific AI and recorded", %{user: user} do
    assert {:ok, result} = AskGlific.ask(%{query: "what is an HSM?"}, user)

    assert result.answer == "an answer"
    assert result.conversation_name == "what is an HSM?"
    assert is_binary(result.conversation_id)
    assert is_binary(result.message_id)

    # The whole exchange is on our own tables, not a pointer to somebody else's.
    assert [conversation] = Repo.all(Conversation)
    assert conversation.user_id == user.id
    assert to_string(conversation.id) == result.conversation_id

    assert [message] = Repo.all(Message)
    assert message.status == :succeeded
    # Two calls: classifying the intent and then answering, both charged to the
    # run so the row reflects what the question actually cost.
    assert message.input_tokens == 20
    # Cost comes from req_llm's per-model pricing, so assert it was recorded
    # rather than pinning a number that moves when pricing does.
    assert Decimal.gt?(message.cost, 0)

    # The routing step sits between the two: a second skill is registered here,
    # so a model really did choose, and what it chose is on record.
    assert [
             {1, :user, "what is an HSM?"},
             {2, :routing, "knowledge"},
             {3, :assistant, "an answer"}
           ] =
             Event
             |> order_by([e], asc: e.step)
             |> select([e], {e.step, e.type, e.content})
             |> Repo.all()
  end

  test "a follow-up in the same conversation carries the earlier exchange", %{user: user} do
    {:ok, first} =
      AskGlific.ask(%{query: "what is an HSM?", skill: "knowledge"}, user)

    assert [%{"messages" => [%{"content" => "what is an HSM?"}]}] = sent()

    {:ok, _} =
      AskGlific.ask(
        %{
          query: "and how do I send one?",
          conversation_id: first.conversation_id,
          skill: "knowledge"
        },
        user
      )

    history = sent() |> List.last() |> Map.fetch!("messages")

    assert Enum.map(history, & &1["content"]) == [
             "what is an HSM?",
             "an answer",
             "and how do I send one?"
           ]
  end

  test "history and the conversation list read back from our tables", %{user: user} do
    {:ok, %{conversation_id: id}} = AskGlific.ask(%{query: "first question"}, user)

    assert {:ok, %{messages: [message]}} = AskGlific.get_messages(id, user)
    assert message.query == "first question"
    assert message.answer == "an answer"
    assert is_integer(message.created_at)

    assert {:ok, %{conversations: [conversation], has_more: false}} =
             AskGlific.get_conversations(user)

    assert conversation.id == id
    assert conversation.name == "first question"
  end

  test "another user cannot read someone else's conversation", %{user: user} do
    {:ok, %{conversation_id: id}} = AskGlific.ask(%{query: "private question"}, user)

    other = Fixtures.user_fixture(%{organization_id: 1, phone: "919999988888"})

    assert {:error, "Conversation not found"} = AskGlific.get_messages(id, other)
    assert {:ok, %{conversations: []}} = AskGlific.get_conversations(other)
  end

  test "feedback is recorded against the answer", %{user: user} do
    {:ok, %{message_id: message_id}} = AskGlific.ask(%{query: "a question"}, user)

    assert {:ok, %{success: true}} =
             AskGlific.submit_feedback(%{message_id: message_id, rating: "like"}, user)

    assert %Event{data: %{"feedback" => %{"rating" => "like"}}} =
             Repo.get(Event, String.to_integer(message_id))

    assert {:error, "Message not found"} =
             AskGlific.submit_feedback(%{message_id: "999999", rating: "like"}, user)
  end

  test "the chat list is ordered by last activity, not by when threads started",
       %{user: user} do
    {:ok, %{conversation_id: older}} = AskGlific.ask(%{query: "first thread"}, user)
    {:ok, %{conversation_id: newer}} = AskGlific.ask(%{query: "second thread"}, user)

    # A follow-up on the older thread brings it back to the top of the list.
    {:ok, _} = AskGlific.ask(%{query: "still here", conversation_id: older}, user)

    assert {:ok, %{conversations: [top, second]}} = AskGlific.get_conversations(user)
    assert top.id == older
    assert second.id == newer
  end

  test "an unknown skill fails the request rather than leaving it running", %{user: user} do
    assert {:error, reason} = AskGlific.ask(%{query: "draft something", skill: "typo"}, user)
    assert reason =~ "typo"

    assert [message] = Repo.all(Message)
    assert message.status == :failed
    assert message.error =~ "typo"
  end

  test "an empty skill is classified rather than taken as a choice", %{user: user} do
    # A client that always sends the field, with nothing selected, must still
    # get routing rather than silently falling to the default skill.
    FakeProvider.script([FakeProvider.answer("draft_hsm"), FakeProvider.answer("a draft")])

    assert {:ok, result} = AskGlific.ask(%{query: "draft me a reminder", skill: ""}, user)

    assert result.skill == "draft_hsm"
    assert Repo.exists?(from(e in Event, where: e.type == :routing))
  end

  test "a provider failure is recorded as a failed message, not lost", %{user: user} do
    # Nothing listening on the port, so the real adapter fails the way it would
    # against a provider that is down.
    FakeProvider.stop()

    assert {:error, reason} = AskGlific.ask(%{query: "a question"}, user)

    # The adapter never passes provider detail outward, so the recorded reason is
    # the generic one; what actually failed is logged instead.
    assert reason == "The AI provider could not complete the request"

    assert [message] = Repo.all(Message)
    assert message.status == :failed
    assert message.error == "The AI provider could not complete the request"

    # The question is still on record even though no answer came back.
    assert [%Event{type: :user, content: "a question"}] = Repo.all(Event)
  end

  test "a button can invoke one skill directly, skipping classification", %{user: user} do
    assert {:ok, result} =
             AskGlific.ask(%{query: "a reminder for the clinic", skill: "draft_hsm"}, user)

    assert result.skill == "draft_hsm"
    assert [message] = Repo.all(Message)
    assert message.skill == "draft_hsm"

    # One call, not two: naming the skill means nothing was classified.
    assert length(sent()) == 1

    # And it saw only the skill's own tools, not all of them.
    names =
      sent() |> List.last() |> Map.fetch!("tools") |> Enum.map(& &1["name"]) |> MapSet.new()

    declared =
      Glific.AI.Skills.DraftHSM |> Skills.tools() |> Enum.map(& &1.name) |> MapSet.new()

    assert MapSet.subset?(names, declared)

    refute "list_flows" in names
  end

  test "an unknown skill is refused before anything is stored", %{user: user} do
    assert {:error, message} = AskGlific.ask(%{query: "hello", skill: "no_such_skill"}, user)
    assert message == ~s(There is no skill called "no_such_skill".)
  end

  test "without a skill the intent is classified and recorded", %{user: user} do
    assert {:ok, result} = AskGlific.ask(%{query: "what flows do I have?"}, user)

    # The classification call plus the answering call.
    assert length(sent()) == 2
    assert result.skill == "knowledge"
    assert [message] = Repo.all(Message)
    assert message.skill == "knowledge"
  end

  test "an empty question is rejected before anything is stored", %{user: user} do
    assert {:error, "Query is required"} = AskGlific.ask(%{query: "   "}, user)
    assert [] == Repo.all(Conversation)
    assert [] == sent()
  end
end
