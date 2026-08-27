defmodule Glific.AI.StorageTest do
  use Glific.DataCase

  import Ecto.Query

  alias Glific.{
    AI.Conversation,
    AI.Event,
    AI.Message,
    Fixtures,
    Repo
  }

  defp conversation(organization_id) do
    user = Fixtures.user_fixture(%{organization_id: organization_id})

    %Conversation{}
    |> Conversation.changeset(%{
      title: "why is my flow stuck?",
      user_id: user.id,
      organization_id: organization_id
    })
    |> Repo.insert!()
  end

  defp message(conversation, attrs \\ %{}) do
    %Message{}
    |> Message.changeset(
      Map.merge(
        %{
          conversation_id: conversation.id,
          user_id: conversation.user_id,
          organization_id: conversation.organization_id,
          skill: "flow-review"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp event(message, attrs) do
    %Event{}
    |> Event.changeset(
      Map.merge(
        %{
          message_id: message.id,
          conversation_id: message.conversation_id,
          organization_id: message.organization_id
        },
        attrs
      )
    )
    |> Repo.insert()
  end

  test "one organization cannot see another's conversations, messages or events" do
    other_org = Fixtures.organization_fixture(%{shortcode: "glific_ai_other"})

    mine = conversation(1)
    my_message = message(mine)
    {:ok, _} = event(my_message, %{step: 1, type: :user, content: "hello"})

    Repo.put_organization_id(other_org.id)

    assert [] == Repo.all(Conversation)
    assert [] == Repo.all(Message)
    assert [] == Repo.all(Event)

    Repo.put_organization_id(1)

    assert [^mine] = Repo.all(Conversation)
    assert 1 == Repo.aggregate(Event, :count)
  end

  test "deleting a conversation removes its messages and events, and the organization FKs cascade" do
    conversation = conversation(1)
    first = message(conversation)
    {:ok, _} = event(first, %{step: 1, type: :assistant, content: "here you go"})

    Repo.delete!(conversation)

    assert 0 == Repo.aggregate(Message, :count)
    assert 0 == Repo.aggregate(Event, :count)

    # An organization being removed must take its Glific AI data with it.
    cascading =
      Repo.all(
        from(c in "pg_constraint",
          join: t in "pg_class",
          on: t.oid == c.conrelid,
          where:
            t.relname in ^[
              "glific_ai_conversations",
              "glific_ai_messages",
              "glific_ai_events"
            ] and
              c.contype == "f" and c.confdeltype == "c",
          select: t.relname,
          distinct: true
        ),
        skip_organization_id: true
      )

    assert Enum.sort(cascading) == [
             "glific_ai_conversations",
             "glific_ai_events",
             "glific_ai_messages"
           ]
  end

  test "two messages in one conversation can both number their steps from 1" do
    conversation = conversation(1)

    # This is the case conversation-wide numbering would break: both messages are
    # live in the same thread and each starts its own event numbering.
    first = message(conversation)
    second = message(conversation, %{skill: "knowledge"})

    assert {:ok, _} = event(first, %{step: 1, type: :user, content: "why is it stuck?"})
    assert {:ok, _} = event(second, %{step: 1, type: :user, content: "and what is an HSM?"})

    assert {:ok, _} =
             event(first, %{
               step: 2,
               type: :tool_call,
               tool_call_id: "call_a1",
               data: %{"name" => "list_flows"}
             })

    # ...but a message may not reuse a step of its own.
    assert {:error, changeset} = event(first, %{step: 1, type: :assistant})
    assert errors_on(changeset).message_id != [] or errors_on(changeset).step != []

    # A whole thread reads back in order across both messages.
    assert [{_, 1}, {_, 2}, {_, 1}] =
             Event
             |> order_by([e], asc: e.message_id, asc: e.step)
             |> select([e], {e.message_id, e.step})
             |> Repo.all()
  end

  test "a failed message keeps its reason and its cost" do
    conversation = conversation(1)

    failed =
      message(conversation, %{
        skill: "flow-review",
        status: :failed,
        error: "the provider returned a 400",
        model: "anthropic:claude-opus-5",
        input_tokens: 120,
        output_tokens: 40,
        cost: Decimal.new("0.0042")
      })

    assert failed.status == :failed
    assert failed.error == "the provider returned a 400"
    assert Decimal.equal?(failed.cost, Decimal.new("0.0042"))

    # A failed message is still listed, so the thread renders.
    assert [failed.id] == Message |> select([r], r.id) |> Repo.all()
  end
end
