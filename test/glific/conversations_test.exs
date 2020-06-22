defmodule Glific.ConversationsTest do
  use Glific.DataCase, async: true
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Contacts
    Conversations.Conversation,
    Messages
  }

  describe "conversation" do
    setup do
      Glific.Seeds.seed_language()
      Glific.Seeds.seed_contacts()
      Glific.Seeds.seed_messages()
      :ok
    end

    test "new/2 will create a conversation object with contact and messages" do
      [contact | _] = Contacts.list_contacts()
      messages = Messages.list_messages()
      conversation = Conversations.Conversation.new(contact, messages)
      assert conversation.id == nil
      assert conversation.contact == contact
      assert conversation.messages == messages
    end

    test "conversation struct will be generate via embedded schema " do
      [contact | _] = Contacts.list_contacts()
      messages = Messages.list_messages()
      conversation = %Conversations.Conversation{contact: contact, messages: messages}
      assert conversation.contact == contact
      assert conversation.messages == messages
    end
  end
end
