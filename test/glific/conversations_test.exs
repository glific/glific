defmodule Glific.ConversationsTest do
  use Glific.DataCase, async: true
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Contacts,
    Conversations.Conversation,
    Messages,
    Seeds.SeedsDev
  }

  describe "conversation" do
    setup do
      default_provider = SeedsDev.seed_providers()
      SeedsDev.seed_organizations(default_provider)
      SeedsDev.seed_contacts()
      SeedsDev.seed_messages()
      :ok
    end

    test "new/2 will create a conversation object with contact and messages", attrs do
      [contact | _] = Contacts.list_contacts(%{filter: attrs})
      messages = Messages.list_messages(%{filter: attrs})
      conversation = Conversation.new(contact, nil, messages)
      assert conversation.id == nil
      assert conversation.contact == contact
      assert conversation.messages == messages
    end

    test "conversation struct will be generate via embedded schema", attrs do
      [contact | _] = Contacts.list_contacts(%{filter: attrs})
      messages = Messages.list_messages(%{filter: attrs})
      conversation = %Conversation{contact: contact, messages: messages}
      assert conversation.contact == contact
      assert conversation.messages == messages
    end
  end
end
