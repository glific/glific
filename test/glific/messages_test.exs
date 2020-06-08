defmodule Glific.MessagesTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Contacts,
    Messages,
    Messages.Message
  }

  describe "messages" do
    @sender_attrs %{
      name: "some sender",
      optin_time: ~U[2010-04-17 14:00:00Z],
      optout_time: ~U[2010-04-17 14:00:00Z],
      phone: "12345671",
      status: :valid,
      wa_status: :invalid
    }

    @recipient_attrs %{
      name: "some recipient",
      optin_time: ~U[2010-04-17 14:00:00Z],
      optout_time: ~U[2010-04-17 14:00:00Z],
      phone: "101013131",
      status: :valid,
      wa_status: :invalid
    }

    @valid_attrs %{
      body: "some body",
      flow: :inbound,
      type: :text,
      wa_message_id: "some wa_message_id",
      wa_status: :enqueued
    }
    @update_attrs %{
      body: "some updated body",
      flow: :inbound,
      type: :text,
      wa_message_id: "some updated wa_message_id"
    }

    @invalid_attrs %{body: nil, flow: nil, type: nil, wa_message_id: nil}

    defp foreign_key_constraint do
      {:ok, sender} = Contacts.create_contact(@sender_attrs)
      {:ok, recipient} = Contacts.create_contact(@recipient_attrs)
      %{sender_id: sender.id, recipient_id: recipient.id}
    end

    def message_fixture(attrs \\ %{}) do
      valid_attrs = Map.merge(@valid_attrs, foreign_key_constraint())

      {:ok, message} =
        valid_attrs
        |> Map.merge(attrs)
        |> Messages.create_message()

      message
    end

    test "list_messages/0 returns all messages" do
      message = message_fixture()
      assert Messages.list_messages() == [message]
    end

    test "list_messages/1 with multiple messages filtered" do
      message = message_fixture()
      assert [message] == Messages.list_messages(%{order: :asc, filter: %{body: message.body}})

      assert [message] ==
               Messages.list_messages(%{order: :asc, filter: %{wa_status: message.wa_status}})
    end

    test "list_messages/1 with foreign key filters" do
      {:ok, sender} = Contacts.create_contact(@sender_attrs)
      {:ok, recipient} = Contacts.create_contact(@recipient_attrs)

      {:ok, message} =
        @valid_attrs
        |> Map.merge(%{sender_id: sender.id, recipient_id: recipient.id})
        |> Messages.create_message()

      assert [message] == Messages.list_messages(%{filter: %{sender: sender.name}})

      assert [message] == Messages.list_messages(%{filter: %{recipient: recipient.name}})

      assert [message] == Messages.list_messages(%{filter: %{either: sender.phone}})

      assert [message] == Messages.list_messages(%{filter: %{either: recipient.phone}})

      assert [] == Messages.list_messages(%{filter: %{either: "ABC"}})
      assert [] == Messages.list_messages(%{filter: %{sender: "ABC"}})
      assert [] == Messages.list_messages(%{filter: %{recipient: "ABC"}})
    end

    test "get_message!/1 returns the message with given id" do
      message = message_fixture()
      assert Messages.get_message!(message.id) == message
    end

    test "create_message/1 with valid data creates a message" do
      assert {:ok, %Message{} = message} =
               @valid_attrs
               |> Map.merge(foreign_key_constraint())
               |> Messages.create_message()
    end

    test "create_message/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Messages.create_message(@invalid_attrs)
    end

    test "update_message/2 with valid data updates the message" do
      message = message_fixture()
      assert {:ok, %Message{} = message} = Messages.update_message(message, @update_attrs)
    end

    test "update_message/2 with invalid data returns error changeset" do
      message = message_fixture()
      assert {:error, %Ecto.Changeset{}} = Messages.update_message(message, @invalid_attrs)
      assert message == Messages.get_message!(message.id)
    end

    test "delete_message/1 deletes the message" do
      message = message_fixture()
      assert {:ok, %Message{}} = Messages.delete_message(message)
      assert_raise Ecto.NoResultsError, fn -> Messages.get_message!(message.id) end
    end

    test "change_message/1 returns a message changeset" do
      message = message_fixture()
      assert %Ecto.Changeset{} = Messages.change_message(message)
    end
  end

  describe "message_media" do
    alias Glific.Messages.MessageMedia

    @valid_attrs %{
      caption: "some caption",
      source_url: "some source_url",
      thumbnail: "some thumbnail",
      url: "some url",
      wa_media_id: "some wa_media_id"
    }
    @update_attrs %{
      caption: "some updated caption",
      source_url: "some updated source_url",
      thumbnail: "some updated thumbnail",
      url: "some updated url",
      wa_media_id: "some updated wa_media_id"
    }
    @invalid_attrs %{caption: nil, source_url: nil, thumbnail: nil, url: nil, wa_media_id: nil}

    def message_media_fixture(attrs \\ %{}) do
      {:ok, message_media} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Messages.create_message_media()

      message_media
    end

    test "list_messages_media/0 returns all message_media" do
      message_media = message_media_fixture()
      assert Messages.list_messages_media() == [message_media]
    end

    test "get_message_media!/1 returns the message_media with given id" do
      message_media = message_media_fixture()
      assert Messages.get_message_media!(message_media.id) == message_media
    end

    test "create_message_media/1 with valid data creates a message_media" do
      assert {:ok, %MessageMedia{} = message_media} = Messages.create_message_media(@valid_attrs)
      assert message_media.caption == "some caption"
      assert message_media.source_url == "some source_url"
      assert message_media.thumbnail == "some thumbnail"
      assert message_media.url == "some url"
      assert message_media.wa_media_id == "some wa_media_id"
    end

    test "create_message_media/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Messages.create_message_media(@invalid_attrs)
    end

    test "update_message_media/2 with valid data updates the message_media" do
      message_media = message_media_fixture()

      assert {:ok, %MessageMedia{} = message_media} =
               Messages.update_message_media(message_media, @update_attrs)

      assert message_media.caption == "some updated caption"
      assert message_media.source_url == "some updated source_url"
      assert message_media.thumbnail == "some updated thumbnail"
      assert message_media.url == "some updated url"
      assert message_media.wa_media_id == "some updated wa_media_id"
    end

    test "update_message_media/2 with invalid data returns error changeset" do
      message_media = message_media_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Messages.update_message_media(message_media, @invalid_attrs)

      assert message_media == Messages.get_message_media!(message_media.id)
    end

    test "delete_message_media/1 deletes the message_media" do
      message_media = message_media_fixture()
      assert {:ok, %MessageMedia{}} = Messages.delete_message_media(message_media)
      assert_raise Ecto.NoResultsError, fn -> Messages.get_message_media!(message_media.id) end
    end

    test "change_message_media/1 returns a message_media changeset" do
      message_media = message_media_fixture()
      assert %Ecto.Changeset{} = Messages.change_message_media(message_media)
    end
  end
end
