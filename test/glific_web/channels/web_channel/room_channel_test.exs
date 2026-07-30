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
  end
end
