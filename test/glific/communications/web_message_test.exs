defmodule Glific.Communications.WebMessageTest do
  use Glific.DataCase
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Communications.WebMessage,
    Contacts,
    Fixtures,
    Messages,
    Providers.Gupshup.Worker,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_contacts(organization)
    :ok
  end

  describe "send_message/2" do
    test "an outbound web send enqueues no gupshup Oban job", %{
      organization_id: organization_id,
      global_schema: global_schema
    } do
      receiver = Fixtures.contact_fixture(%{organization_id: organization_id})

      {:ok, _message} =
        Messages.create_and_send_message(%{
          body: "hello from the web",
          type: :text,
          channel: "web",
          receiver_id: receiver.id,
          organization_id: organization_id
        })

      refute_enqueued(worker: Worker, prefix: global_schema)
    end

    test "marks bsp_status :error when the contact's browser is not connected", %{
      organization_id: organization_id
    } do
      receiver = Fixtures.contact_fixture(%{organization_id: organization_id})

      {:ok, message} =
        Messages.create_and_send_message(%{
          body: "hello from the web",
          type: :text,
          channel: "web",
          receiver_id: receiver.id,
          organization_id: organization_id
        })

      sent_message = Messages.get_message!(message.id)
      assert sent_message.bsp_status == :error
      assert sent_message.status == :sent
      assert sent_message.channel == "web"
    end

    test "sends the message and publishes without error (sent_message topic)", %{
      organization_id: organization_id
    } do
      receiver = Fixtures.contact_fixture(%{organization_id: organization_id})

      message =
        Fixtures.message_fixture(%{
          type: :text,
          channel: "web",
          flow: :outbound,
          receiver_id: receiver.id,
          organization_id: organization_id
        })

      # `WebMessage.send_message/2` calls `Communications.publish_data/3` with the existing
      # `:sent_message` topic (same one Communications.Message uses for WhatsApp sends) so the
      # staff inbox stays realtime for the web channel too. A successful `{:ok, _}` return here
      # confirms that publish call executed without raising.
      assert {:ok, sent_message} = WebMessage.send_message(message, %{})
      assert sent_message.id == message.id
    end

    test "an interactive-typed web message is delivered via send_interactive", %{
      organization_id: organization_id
    } do
      receiver = Fixtures.contact_fixture(%{organization_id: organization_id})

      interactive_content = %{
        "type" => "quick_reply",
        "content" => %{"type" => "text", "text" => "pick one"},
        "options" => [%{"type" => "text", "title" => "yes"}, %{"type" => "text", "title" => "no"}]
      }

      message =
        Fixtures.message_fixture(%{
          type: :quick_reply,
          interactive_content: interactive_content,
          channel: "web",
          flow: :outbound,
          receiver_id: receiver.id,
          organization_id: organization_id
        })

      # Before interactive support, :quick_reply had no @type_to_token entry, so this
      # raised and fell to the rescue as {:error, _}. It now dispatches to send_interactive.
      assert {:ok, sent_message} = WebMessage.send_message(message, %{})
      assert sent_message.id == message.id
    end
  end

  describe "receive_message/2" do
    test "persists an inbound channel:web message and triggers processing", %{
      organization_id: organization_id
    } do
      phone = Faker.Phone.EnUs.phone()

      :ok =
        WebMessage.receive_message(%{
          sender: %{phone: phone, organization_id: organization_id},
          organization_id: organization_id,
          body: "hi there"
        })

      {:ok, contact} =
        Contacts.maybe_create_contact(%{phone: phone, organization_id: organization_id})

      [message] = Messages.list_conversation_messages(contact.id, "web", %{limit: 10, offset: 0})

      assert message.body == "hi there"
      assert message.channel == "web"
      assert message.flow == :inbound
      assert message.bsp_status == :delivered
    end

    test "persists an inbound :image message with a linked media row", %{
      organization_id: organization_id
    } do
      phone = Faker.Phone.EnUs.phone()

      :ok =
        WebMessage.receive_message(
          %{
            sender: %{phone: phone, organization_id: organization_id},
            organization_id: organization_id,
            body: "a photo",
            url: "http://example.com/photo.jpg",
            source_url: "http://example.com/photo.jpg",
            content_type: "image/jpeg"
          },
          :image
        )

      {:ok, contact} =
        Contacts.maybe_create_contact(%{phone: phone, organization_id: organization_id})

      [message] = Messages.list_conversation_messages(contact.id, "web", %{limit: 10, offset: 0})

      assert message.channel == "web"
      assert message.flow == :inbound
      assert message.type == :image
      refute is_nil(message.media_id)

      media = Messages.get_message_media!(message.media_id)
      assert media.url == "http://example.com/photo.jpg"
    end

    test "persists an inbound :location message with a location row", %{
      organization_id: organization_id
    } do
      phone = Faker.Phone.EnUs.phone()

      :ok =
        WebMessage.receive_message(
          %{
            sender: %{phone: phone, organization_id: organization_id},
            organization_id: organization_id,
            body: "https://www.google.com/maps?q=12.9,77.5",
            latitude: 12.9,
            longitude: 77.5
          },
          :location
        )

      {:ok, contact} =
        Contacts.maybe_create_contact(%{phone: phone, organization_id: organization_id})

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
