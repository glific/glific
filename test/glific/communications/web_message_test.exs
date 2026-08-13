defmodule Glific.Communications.WebMessageTest do
  use Glific.DataCase
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Communications.WebMessage,
    Contacts,
    Fixtures,
    Messages,
    Notifications,
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

    test "a blocks-typed web message is delivered via send_blocks", %{
      organization_id: organization_id
    } do
      receiver = Fixtures.contact_fixture(%{organization_id: organization_id})

      # Stored as the widget/messages.interactive_content shape sees it: unwrapped.
      interactive_content = %{
        "type" => "blocks",
        "version" => 1,
        "component" => "glific/image-panel",
        "props" => %{
          "id" => "course",
          "options" => [%{"id" => "c1", "image" => "https://example.com/1.png", "label" => "A"}]
        }
      }

      message =
        Fixtures.message_fixture(%{
          type: :blocks,
          interactive_content: interactive_content,
          channel: "web",
          flow: :outbound,
          receiver_id: receiver.id,
          organization_id: organization_id
        })

      assert {:ok, sent_message} = WebMessage.send_message(message, %{})
      assert sent_message.id == message.id
    end
  end

  describe "blocks unsupported-channel fallback (Messages.create_and_send_message/1)" do
    test "sends the derived body as plain text and raises a flow notification", %{
      organization_id: organization_id
    } do
      receiver = Fixtures.contact_fixture(%{organization_id: organization_id})
      flow = Fixtures.flow_fixture(%{organization_id: organization_id})

      {:ok, message} =
        Messages.create_and_send_message(%{
          type: "blocks",
          body: "Reply with a course",
          channel: "whatsapp",
          receiver_id: receiver.id,
          organization_id: organization_id,
          flow_id: flow.id,
          uuid: Ecto.UUID.generate(),
          interactive_content: %{
            "type" => "blocks",
            "version" => 1,
            "component" => "glific/image-panel",
            "props" => %{
              "id" => "course",
              "options" => [
                %{"id" => "c1", "image" => "https://example.com/1.png", "label" => "A"}
              ]
            }
          }
        })

      assert message.type == :text
      assert message.body == "Reply with a course"

      notifications =
        Notifications.list_notifications(%{filter: %{organization_id: organization_id}})

      assert Enum.any?(
               notifications,
               &String.contains?(&1.message, "does not support Blocks")
             )
    end
  end

  describe "receive_message/2 — blocks_response" do
    setup %{organization_id: organization_id} do
      contact = Fixtures.contact_fixture(%{organization_id: organization_id})

      interactive_content = %{
        "type" => "blocks",
        "version" => 1,
        "component" => "glific/image-panel",
        "props" => %{
          "id" => "course",
          "options" => [
            %{"id" => "c1", "image" => "https://example.com/1.png", "label" => "Spoken English"},
            %{"id" => "c2", "image" => "https://example.com/2.png", "label" => "Digital skills"}
          ]
        }
      }

      outbound =
        Fixtures.message_fixture(%{
          type: :blocks,
          interactive_content: interactive_content,
          channel: "web",
          flow: :outbound,
          receiver_id: contact.id,
          organization_id: organization_id
        })

      %{contact: contact, outbound: outbound}
    end

    test "accepts a valid response, persists it, and marks the outbound message answered", %{
      organization_id: organization_id,
      contact: contact,
      outbound: outbound
    } do
      assert {:ok, inbound} =
               WebMessage.receive_message(
                 %{
                   "message_id" => outbound.id,
                   "component" => "glific/image-panel",
                   "values" => %{"course" => "c2"},
                   "summary" => "Picked Digital skills",
                   sender: %{phone: contact.phone},
                   organization_id: organization_id
                 },
                 :blocks_response
               )

      assert inbound.type == :blocks_response
      assert inbound.body == "Picked Digital skills"
      assert inbound.context_message_id == outbound.id
      assert inbound.channel == "web"
      assert inbound.flow == :inbound

      answered_outbound = Messages.get_message!(outbound.id)
      assert answered_outbound.interactive_content["answered"] == true
      assert answered_outbound.interactive_content["answer_summary"] == "Picked Digital skills"
    end

    test "rejects a duplicate response to an already-answered message", %{
      organization_id: organization_id,
      contact: contact,
      outbound: outbound
    } do
      params = %{
        "message_id" => outbound.id,
        "component" => "glific/image-panel",
        "values" => %{"course" => "c2"},
        "summary" => "Picked Digital skills",
        sender: %{phone: contact.phone},
        organization_id: organization_id
      }

      assert {:ok, _first_response} = WebMessage.receive_message(params, :blocks_response)
      assert {:error, _reason} = WebMessage.receive_message(params, :blocks_response)
    end

    test "rejects a response for a message belonging to another contact", %{
      organization_id: organization_id,
      outbound: outbound
    } do
      other_contact = Fixtures.contact_fixture(%{organization_id: organization_id})

      assert {:error, _reason} =
               WebMessage.receive_message(
                 %{
                   "message_id" => outbound.id,
                   "component" => "glific/image-panel",
                   "values" => %{"course" => "c2"},
                   "summary" => "Picked Digital skills",
                   sender: %{phone: other_contact.phone},
                   organization_id: organization_id
                 },
                 :blocks_response
               )
    end

    test "rejects an oversized/invalid response and does not consume the single-submit slot", %{
      organization_id: organization_id,
      contact: contact,
      outbound: outbound
    } do
      assert {:error, reason} =
               WebMessage.receive_message(
                 %{
                   "message_id" => outbound.id,
                   "component" => "glific/image-panel",
                   "values" => %{"course" => "c2"},
                   "summary" => String.duplicate("x", 501),
                   sender: %{phone: contact.phone},
                   organization_id: organization_id
                 },
                 :blocks_response
               )

      assert reason =~ "exceeds"

      still_unanswered = Messages.get_message!(outbound.id)
      refute still_unanswered.interactive_content["answered"] == true

      # The slot must still be usable with a valid response.
      assert {:ok, _inbound} =
               WebMessage.receive_message(
                 %{
                   "message_id" => outbound.id,
                   "component" => "glific/image-panel",
                   "values" => %{"course" => "c2"},
                   "summary" => "Picked Digital skills",
                   sender: %{phone: contact.phone},
                   organization_id: organization_id
                 },
                 :blocks_response
               )
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
