defmodule GlificWeb.WebChannel.RoomChannelTest do
  use GlificWeb.ChannelCase

  alias Glific.{
    Fixtures,
    Messages,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  alias GlificWeb.WebChannel.Token
  alias GlificWeb.WebChannelSocket

  setup do
    Repo.put_organization_id(1)
    Repo.put_current_user(Fixtures.user_fixture(%{name: "NGO Test Admin", roles: ["manager"]}))

    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_contacts(organization)
    Partners.get_organization!(1) |> Partners.fill_cache()

    contact = Fixtures.contact_fixture(%{organization_id: 1})

    %{contact: contact}
  end

  @spec connect_socket(Glific.Contacts.Contact.t()) :: Phoenix.Socket.t()
  defp connect_socket(contact) do
    token = Token.sign_contact_token(contact)
    {:ok, socket} = connect(WebChannelSocket, %{"token" => token})
    socket
  end

  describe "join/3" do
    test "is rejected when the topic's contact_id does not match the authenticated contact", %{
      contact: contact
    } do
      other_contact = Fixtures.contact_fixture(%{organization_id: 1})
      socket = connect_socket(contact)

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, "web_channel:#{other_contact.id}", %{})
    end

    test "replies with the last 100 messages for the contact's own topic", %{contact: contact} do
      {:ok, message} =
        Messages.create_message(%{
          body: "history message",
          type: :text,
          flow: :inbound,
          channel: "web",
          sender_id: contact.id,
          contact_id: contact.id,
          receiver_id: Partners.organization_contact_id(1),
          organization_id: 1,
          bsp_status: :delivered,
          status: :received
        })

      socket = connect_socket(contact)

      assert {:ok, %{messages: messages}, _socket} =
               subscribe_and_join(socket, "web_channel:#{contact.id}", %{})

      assert Enum.any?(messages, &(&1.id == message.id))
    end

    test "serializes interactive_content and type in the join reply", %{contact: contact} do
      interactive_content = %{
        "type" => "quick_reply",
        "content" => %{"type" => "text", "text" => "pick one"},
        "options" => [%{"type" => "text", "title" => "yes"}, %{"type" => "text", "title" => "no"}]
      }

      {:ok, message} =
        Messages.create_message(%{
          body: "pick one",
          type: :quick_reply,
          interactive_content: interactive_content,
          flow: :outbound,
          channel: "web",
          sender_id: Partners.organization_contact_id(1),
          contact_id: contact.id,
          receiver_id: contact.id,
          organization_id: 1,
          bsp_status: :delivered,
          status: :sent
        })

      socket = connect_socket(contact)

      assert {:ok, %{messages: messages}, _socket} =
               subscribe_and_join(socket, "web_channel:#{contact.id}", %{})

      serialized = Enum.find(messages, &(&1.id == message.id))
      assert serialized.type == :quick_reply
      assert serialized.interactive_content == interactive_content
    end
  end

  describe "handle_in/3" do
    test "new_message persists an inbound channel:web message", %{contact: contact} do
      socket = connect_socket(contact)

      {:ok, _reply, socket} = subscribe_and_join(socket, "web_channel:#{contact.id}", %{})

      ref = push(socket, "new_message", %{"body" => "hello from the browser"})
      assert_reply(ref, :ok)

      [message] = Messages.list_conversation_messages(contact.id, "web", %{limit: 10, offset: 0})

      assert message.body == "hello from the browser"
      assert message.channel == "web"
      assert message.flow == :inbound
    end

    test "update_name renames the contact", %{contact: contact} do
      socket = connect_socket(contact)

      {:ok, _reply, socket} = subscribe_and_join(socket, "web_channel:#{contact.id}", %{})

      ref = push(socket, "update_name", %{"name" => "New Contact Name"})
      assert_reply(ref, :ok)

      updated_contact = Glific.Contacts.get_contact!(contact.id)
      assert updated_contact.name == "New Contact Name"
    end

    test "new_media_message persists an inbound channel:web image message", %{contact: contact} do
      socket = connect_socket(contact)

      {:ok, _reply, socket} = subscribe_and_join(socket, "web_channel:#{contact.id}", %{})

      ref =
        push(socket, "new_media_message", %{
          "type" => "image",
          "url" => "http://example.com/x.jpg",
          "content_type" => "image/jpeg",
          "caption" => "look"
        })

      assert_reply(ref, :ok)

      [message] = Messages.list_conversation_messages(contact.id, "web", %{limit: 10, offset: 0})

      assert message.channel == "web"
      assert message.flow == :inbound
      assert message.type == :image
      refute is_nil(message.media_id)
    end

    test "new_media_message replies with an error for an unsupported type", %{contact: contact} do
      socket = connect_socket(contact)

      {:ok, _reply, socket} = subscribe_and_join(socket, "web_channel:#{contact.id}", %{})

      ref =
        push(socket, "new_media_message", %{
          "type" => "sticker",
          "url" => "http://example.com/x.webp"
        })

      assert_reply(ref, :error, %{reason: "unsupported media type"})
    end

    test "new_location_message persists an inbound channel:web location message", %{
      contact: contact
    } do
      socket = connect_socket(contact)

      {:ok, _reply, socket} = subscribe_and_join(socket, "web_channel:#{contact.id}", %{})

      ref = push(socket, "new_location_message", %{"latitude" => 12.9, "longitude" => 77.5})
      assert_reply(ref, :ok)

      [message] = Messages.list_conversation_messages(contact.id, "web", %{limit: 10, offset: 0})

      assert message.channel == "web"
      assert message.flow == :inbound
      assert message.type == :location

      location =
        Repo.get_by!(Glific.Contacts.Location, contact_id: contact.id, message_id: message.id)

      assert location.latitude == 12.9
      assert location.longitude == 77.5
    end
  end
end
