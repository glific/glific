defmodule Glific.MessageConversationsTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Fixtures,
    MessageConversations,
    Messages.MessageConversation
  }

  describe "message_conversations" do
    @valid_attrs %{
      conversation_id: "some more conversation id",
      deduction_type: "some more deduction type",
      is_billable: true,
      payload: %{}
    }
    @invalid_attrs %{
      conversation_id: nil,
      deduction_type: nil,
      is_billable: true,
      payload: %{}
    }
    @update_attrs %{
      conversation_id: "updated conversation id",
      deduction_type: "updated deduction type"
    }

    test "get_message_conversation!/1 returns the message_conversation with given id" do
      message_conversations = Fixtures.message_conversations()

      assert MessageConversations.get_message_conversation!(message_conversations.id) ==
               message_conversations
    end

    test "create_message_conversation/1 with valid data creates a message_conversation", %{
      organization_id: organization_id
    } do
      message = Fixtures.message_fixture()

      attrs =
        Map.merge(@valid_attrs, %{
          organization_id: organization_id,
          contact_id: message.sender_id,
          message_id: message.id
        })

      assert {:ok, %MessageConversation{} = message_conversation} =
               MessageConversations.create_message_conversation(attrs)

      assert message_conversation.conversation_id == "some more conversation id"
      assert message_conversation.is_billable == true
      assert message_conversation.deduction_type == "some more deduction type"
      assert message_conversation.organization_id == organization_id
    end

    test "create_message_conversation/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               MessageConversations.create_message_conversation(@invalid_attrs)
    end

    test "update_message_conversation/2 with valid data updates the message_conversation", %{
      organization_id: organization_id
    } do
      message_conversations = Fixtures.message_conversations()
      attrs = Map.merge(@update_attrs, %{organization_id: organization_id})

      assert {:ok, %MessageConversation{} = message_conversations} =
               MessageConversations.update_message_conversation(message_conversations, attrs)

      assert message_conversations.conversation_id == "updated conversation id"
      assert message_conversations.deduction_type == "updated deduction type"
      assert message_conversations.organization_id == organization_id
    end

    test "update_message_conversation/2 with invalid data returns error changeset" do
      message_conversations = Fixtures.message_conversations()

      assert {:error, %Ecto.Changeset{}} =
               MessageConversations.update_message_conversation(
                 message_conversations,
                 @invalid_attrs
               )

      assert message_conversations ==
               MessageConversations.get_message_conversation!(message_conversations.id)
    end

    test "delete_message_conversation/1 deletes the message_conversation" do
      message_conversations = Fixtures.message_conversations()

      assert {:ok, %MessageConversation{}} =
               MessageConversations.delete_message_conversation(message_conversations)

      assert_raise Ecto.NoResultsError, fn ->
        MessageConversations.get_message_conversation!(message_conversations.id)
      end
    end
  end
end
