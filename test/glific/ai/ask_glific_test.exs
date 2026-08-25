defmodule Glific.AI.AskGlificTest do
  use Glific.DataCase

  alias Glific.{
    AI.Conversation,
    AI.Event,
    AI.Message,
    AI.Request,
    AI.Usage,
    AskGlific,
    Fixtures,
    Repo
  }

  defmodule EchoProvider do
    @moduledoc false
    @behaviour Glific.AI.Provider

    @impl Glific.AI.Provider
    def generate(messages, _opts) do
      send(self(), {:asked_with, messages})

      {:ok, Message.assistant("an answer"),
       %Usage{input_tokens: 20, output_tokens: 6, cost: Decimal.new("0.0011")}}
    end
  end

  defmodule FailingProvider do
    @moduledoc false
    @behaviour Glific.AI.Provider

    @impl Glific.AI.Provider
    def generate(_messages, _opts), do: {:error, {:provider_error, "upstream timeout"}}
  end

  setup do
    original = Application.get_env(:glific, Glific.AI)
    on_exit(fn -> Application.put_env(:glific, Glific.AI, original) end)
    FunWithFlags.enable(:glific_ai_enabled, for_actor: %{organization_id: 1})
    %{user: Fixtures.user_fixture(%{organization_id: 1})}
  end

  defp use_provider(provider) do
    Application.put_env(
      :glific,
      Glific.AI,
      Keyword.put(Application.get_env(:glific, Glific.AI), :provider, provider)
    )
  end

  test "with the flag on, a question is answered by Glific AI and recorded", %{user: user} do
    use_provider(EchoProvider)

    assert {:ok, result} = AskGlific.ask(%{query: "what is an HSM?"}, user)

    assert result.answer == "an answer"
    assert result.conversation_name == "what is an HSM?"
    assert is_binary(result.conversation_id)
    assert is_binary(result.message_id)

    # The whole exchange is on our own tables, not a pointer to somebody else's.
    assert [conversation] = Repo.all(Conversation)
    assert conversation.user_id == user.id
    assert to_string(conversation.id) == result.conversation_id

    assert [request] = Repo.all(Request)
    assert request.status == :succeeded
    assert request.skill == "knowledge"
    assert request.input_tokens == 20
    assert Decimal.equal?(request.cost, Decimal.new("0.0011"))

    assert [{1, :user, "what is an HSM?"}, {2, :assistant, "an answer"}] =
             Event
             |> order_by([e], asc: e.step)
             |> select([e], {e.step, e.type, e.content})
             |> Repo.all()
  end

  test "a follow-up in the same conversation carries the earlier exchange", %{user: user} do
    use_provider(EchoProvider)

    {:ok, first} = AskGlific.ask(%{query: "what is an HSM?"}, user)
    assert_received {:asked_with, [%Message{content: "what is an HSM?"}]}

    {:ok, _} =
      AskGlific.ask(
        %{query: "and how do I send one?", conversation_id: first.conversation_id},
        user
      )

    assert_received {:asked_with, history}

    assert Enum.map(history, & &1.content) == [
             "what is an HSM?",
             "an answer",
             "and how do I send one?"
           ]
  end

  test "history and the conversation list read back from our tables", %{user: user} do
    use_provider(EchoProvider)

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
    use_provider(EchoProvider)
    {:ok, %{conversation_id: id}} = AskGlific.ask(%{query: "private question"}, user)

    other = Fixtures.user_fixture(%{organization_id: 1, phone: "919999988888"})

    assert {:error, "Conversation not found"} = AskGlific.get_messages(id, other)
    assert {:ok, %{conversations: []}} = AskGlific.get_conversations(other)
  end

  test "feedback is recorded against the answer", %{user: user} do
    use_provider(EchoProvider)
    {:ok, %{message_id: message_id}} = AskGlific.ask(%{query: "a question"}, user)

    assert {:ok, %{success: true}} =
             AskGlific.submit_feedback(%{message_id: message_id, rating: "like"}, user)

    assert %Event{data: %{"feedback" => %{"rating" => "like"}}} =
             Repo.get(Event, String.to_integer(message_id))

    assert {:error, "Message not found"} =
             AskGlific.submit_feedback(%{message_id: "999999", rating: "like"}, user)
  end

  test "a provider failure is recorded as a failed request, not lost", %{user: user} do
    use_provider(FailingProvider)

    assert {:error, "upstream timeout"} = AskGlific.ask(%{query: "a question"}, user)

    assert [request] = Repo.all(Request)
    assert request.status == :failed
    assert request.error == "upstream timeout"

    # The question is still on record even though no answer came back.
    assert [%Event{type: :user, content: "a question"}] = Repo.all(Event)
  end

  test "an empty question is rejected before anything is stored", %{user: user} do
    use_provider(EchoProvider)

    assert {:error, "Query is required"} = AskGlific.ask(%{query: "   "}, user)
    assert [] == Repo.all(Conversation)
    refute_received {:asked_with, _}
  end
end
