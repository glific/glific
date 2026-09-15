defmodule Glific.Communications.WebMessageTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Communications.WebMessage,
    Contacts,
    Contacts.Contact,
    Contacts.Location,
    Fixtures,
    Messages.Message,
    Processor.MessageWorker,
    Repo,
    WebChannelFlagHelpers
  }

  setup do
    %{contact: Fixtures.contact_fixture()}
  end

  describe "receive_message/2 text" do
    test "persists an inbound text message on the web channel", %{contact: contact} do
      assert {:ok, message} =
               WebMessage.receive_message(
                 %{
                   sender: %{phone: contact.phone},
                   organization_id: contact.organization_id,
                   body: "hello there"
                 },
                 :text
               )

      assert message.body == "hello there"
      assert message.type == :text
      assert message.flow == :inbound
      assert message.channel == :web
      assert message.contact_id == contact.id
      assert message.sender_id == contact.id
      assert message.bsp_message_id == nil
    end

    test "reuses an existing contact by phone rather than creating a duplicate", %{
      contact: contact
    } do
      assert {:ok, message} =
               WebMessage.receive_message(
                 %{
                   sender: %{phone: contact.phone},
                   organization_id: contact.organization_id,
                   body: "hi again"
                 },
                 :text
               )

      assert message.contact_id == contact.id
    end
  end

  describe "the WhatsApp session window" do
    # last_message_at is the WhatsApp 24-hour window; a browser message must not open it, or a
    # contact who only ever wrote on the web — and, post-#5713, may never have consented to
    # WhatsApp — would look messageable there for 24 hours.
    test "an inbound web message does not touch contacts.last_message_at", %{contact: contact} do
      {:ok, contact} = Contacts.update_contact(contact, %{last_message_at: nil})

      assert {:ok, _message} =
               WebMessage.receive_message(
                 %{
                   sender: %{phone: contact.phone},
                   organization_id: contact.organization_id,
                   body: "sent from the browser"
                 },
                 :text
               )

      assert %Contact{last_message_at: nil} = Repo.get!(Contact, contact.id)
    end

    # The rest of the inbox state is channel-agnostic and still has to update, or a web
    # conversation would neither surface nor sort in the shared inbox.
    test "an inbound web message still bumps last_communication_at and unread state",
         %{contact: contact} do
      before = Repo.get!(Contact, contact.id)

      assert {:ok, _message} =
               WebMessage.receive_message(
                 %{
                   sender: %{phone: contact.phone},
                   organization_id: contact.organization_id,
                   body: "sent from the browser"
                 },
                 :text
               )

      after_contact = Repo.get!(Contact, contact.id)

      assert DateTime.compare(after_contact.last_communication_at, before.last_communication_at) in [
               :gt,
               :eq
             ]

      assert after_contact.is_org_read == false
      assert after_contact.last_message_number > before.last_message_number
    end
  end

  describe "receive_message/2 media" do
    test "creates the messages_media row and the message in one transaction", %{
      contact: contact
    } do
      assert {:ok, message} =
               WebMessage.receive_message(
                 %{
                   sender: %{phone: contact.phone},
                   organization_id: contact.organization_id,
                   url: "https://storage.googleapis.com/test-bucket/some/image.png",
                   source_url: "https://storage.googleapis.com/test-bucket/some/image.png",
                   caption: "a caption",
                   content_type: "image/png",
                   body: "a caption"
                 },
                 :image
               )

      message = Repo.preload(message, :media)
      assert message.type == :image
      assert message.channel == :web
      assert message.media != nil
      assert message.media.url == "https://storage.googleapis.com/test-bucket/some/image.png"
    end

    # The caller is a socket handler, so a raise here would stop the channel rather than reply,
    # and the widget would see a teardown instead of the error its retry path is built on.
    test "returns an error rather than raising when the media row cannot be created", %{
      contact: contact
    } do
      message_count = Repo.aggregate(Message, :count)

      assert {:error, %Ecto.Changeset{}} =
               WebMessage.receive_message(
                 %{
                   sender: %{phone: contact.phone},
                   organization_id: contact.organization_id,
                   url: nil,
                   source_url: nil,
                   body: ""
                 },
                 :image
               )

      assert Repo.aggregate(Message, :count) == message_count
    end
  end

  describe "receive_message/2 location" do
    test "creates the message before the locations row", %{contact: contact} do
      assert {:ok, message} =
               WebMessage.receive_message(
                 %{
                   sender: %{phone: contact.phone},
                   organization_id: contact.organization_id,
                   latitude: 12.34,
                   longitude: 56.78,
                   body: "https://www.google.com/maps?q=12.34,56.78"
                 },
                 :location
               )

      assert message.type == :location
      assert message.channel == :web

      location = Repo.get_by!(Location, message_id: message.id)
      assert location.longitude == 56.78
      assert location.latitude == 12.34
    end
  end

  test "never touches session_status: inbound web messages don't apply the WhatsApp session window",
       %{contact: contact} do
    # last_message_at comes from a DB trigger; bsp_status is the WhatsApp session concept and
    # only set_session_status/2 writes it, which this path never calls.
    before_message = Repo.get!(Contact, contact.id)

    assert {:ok, _message} =
             WebMessage.receive_message(
               %{
                 sender: %{phone: contact.phone},
                 organization_id: contact.organization_id,
                 body: "hello"
               },
               :text
             )

    after_message = Repo.get!(Contact, contact.id)
    assert after_message.bsp_status == before_message.bsp_status
  end

  describe "with the web channel off, nothing reaches the flow engine" do
    # Flag off (the suite default): the message is persisted but must not enter the flow engine.
    test "a text message never enqueues MessageWorker", %{contact: contact} do
      assert {:ok, _message} =
               WebMessage.receive_message(
                 %{
                   sender: %{phone: contact.phone},
                   organization_id: contact.organization_id,
                   body: "hello there"
                 },
                 :text
               )

      refute_enqueued(worker: MessageWorker, prefix: "global")
    end

    test "a media message never enqueues MessageWorker", %{contact: contact} do
      assert {:ok, _message} =
               WebMessage.receive_message(
                 %{
                   sender: %{phone: contact.phone},
                   organization_id: contact.organization_id,
                   url: "https://storage.googleapis.com/test-bucket/some/image.png",
                   source_url: "https://storage.googleapis.com/test-bucket/some/image.png",
                   caption: "a caption",
                   content_type: "image/png",
                   body: "a caption"
                 },
                 :image
               )

      refute_enqueued(worker: MessageWorker, prefix: "global")
    end

    test "a location message never enqueues MessageWorker", %{contact: contact} do
      assert {:ok, _message} =
               WebMessage.receive_message(
                 %{
                   sender: %{phone: contact.phone},
                   organization_id: contact.organization_id,
                   latitude: 12.34,
                   longitude: 56.78,
                   body: "https://www.google.com/maps?q=12.34,56.78"
                 },
                 :location
               )

      refute_enqueued(worker: MessageWorker, prefix: "global")
    end
  end

  describe "with the web channel on, the message reaches the flow engine" do
    # This is what lets a web keyword trigger its flow and a mid-flow reply advance it — the same
    # MessageWorker path WhatsApp inbound uses.
    test "a text message enqueues MessageWorker", %{contact: contact} do
      WebChannelFlagHelpers.with_web_channel_enabled(contact.organization_id, fn ->
        assert {:ok, message} =
                 WebMessage.receive_message(
                   %{
                     sender: %{phone: contact.phone},
                     organization_id: contact.organization_id,
                     body: "hello there"
                   },
                   :text
                 )

        assert_enqueued(
          worker: MessageWorker,
          args: %{message_id: message.id, organization_id: contact.organization_id},
          prefix: "global"
        )
      end)
    end

    test "a location message enqueues MessageWorker", %{contact: contact} do
      WebChannelFlagHelpers.with_web_channel_enabled(contact.organization_id, fn ->
        assert {:ok, message} =
                 WebMessage.receive_message(
                   %{
                     sender: %{phone: contact.phone},
                     organization_id: contact.organization_id,
                     latitude: 12.34,
                     longitude: 56.78,
                     body: "https://www.google.com/maps?q=12.34,56.78"
                   },
                   :location
                 )

        assert_enqueued(worker: MessageWorker, args: %{message_id: message.id}, prefix: "global")
      end)
    end
  end
end
