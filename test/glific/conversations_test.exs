defmodule Glific.ConversationsTest do
  use Glific.DataCase, async: true
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Contacts,
    Conversations.Conversation,
    Messages
  }

  describe "conversation" do
    setup do
      default_provider = Glific.Seeds.seed_providers()
      Glific.Seeds.seed_organizations(default_provider)
      Glific.Seeds.seed_contacts()
      Glific.Seeds.seed_messages()
      :ok
    end

    test "new/2 will create a conversation object with contact and messages" do
      [contact | _] = Contacts.list_contacts()
      messages = Messages.list_messages()
      conversation = Conversation.new(contact, messages)
      assert conversation.id == nil
      assert conversation.contact == contact
      assert conversation.messages == messages
    end

    test "conversation struct will be generate via embedded schema " do
      [contact | _] = Contacts.list_contacts()
      messages = Messages.list_messages()
      conversation = %Conversation{contact: contact, messages: messages}
      assert conversation.contact == contact
      assert conversation.messages == messages
    end
  end
end
