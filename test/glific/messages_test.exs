defmodule Glific.MessagesTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Faker.Phone

  alias Glific.{
    Contacts,
    Messages,
    Messages.Message
  }

  alias Glific.Fixtures

  describe "messages" do
    alias Glific.Providers.Gupshup.Worker
    alias Glific.Settings

    setup do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "submitted",
                "messageId" => Faker.String.base64(36)
              })
          }
      end)

      :ok
    end

    @sender_attrs %{
      name: "some sender",
      optin_time: ~U[2010-04-17 14:00:00Z],
      optout_time: ~U[2010-04-17 14:00:00Z],
      phone: "12345671",
      last_message_at: DateTime.utc_now()
    }

    @receiver_attrs %{
      name: "some receiver",
      optin_time: ~U[2010-04-17 14:00:00Z],
      optout_time: ~U[2010-04-17 14:00:00Z],
      phone: "101013131",
      last_message_at: DateTime.utc_now()
    }

    @valid_attrs %{
      body: "some body",
      flow: :inbound,
      type: :text,
      provider_message_id: "some provider_message_id",
      provider_status: :enqueued
    }
    @update_attrs %{
      body: "some updated body",
      flow: :inbound,
      type: :text,
      provider_message_id: "some updated provider_message_id"
    }

    @invalid_attrs %{body: nil, flow: nil, type: nil, provider_message_id: nil}

    @valid_default_organization_language_attrs %{
      label: "English (United States)",
      label_locale: "English",
      locale: "en_US",
      is_active: true
    }

    def default_organization_language_fixture() do
      {:ok, default_organization_language} =
        @valid_default_organization_language_attrs
        |> Settings.language_upsert()

      default_organization_language
    end

    defp foreign_key_constraint do
      default_organization_language = default_organization_language_fixture()

      {:ok, sender} =
        @sender_attrs
        |> Map.merge(%{phone: Phone.EnUs.phone(), language_id: default_organization_language.id})
        |> Contacts.create_contact()

      {:ok, receiver} =
        @receiver_attrs
        |> Map.merge(%{phone: Phone.EnUs.phone(), language_id: default_organization_language.id})
        |> Contacts.create_contact()

      %{sender_id: sender.id, receiver_id: receiver.id}
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

      assert [message] ==
               Messages.list_messages(%{opts: %{order: :asc}, filter: %{body: message.body}})

      assert [message] ==
               Messages.list_messages(%{
                 opts: %{order: :asc},
                 filter: %{provider_status: message.provider_status}
               })
    end

    test "count_messages/0 returns count of all messages" do
      _ = message_fixture()
      assert Messages.count_messages() == 1

      assert Messages.count_messages(%{filter: %{body: "some body"}}) == 1
    end

    test "list_messages/1 with foreign key filters" do
      default_organization_language = default_organization_language_fixture()

      {:ok, sender} =
        @sender_attrs
        |> Map.merge(%{phone: Phone.EnUs.phone(), language_id: default_organization_language.id})
        |> Contacts.create_contact()

      {:ok, receiver} =
        @receiver_attrs
        |> Map.merge(%{phone: Phone.EnUs.phone(), language_id: default_organization_language.id})
        |> Contacts.create_contact()

      {:ok, message} =
        @valid_attrs
        |> Map.merge(%{sender_id: sender.id, receiver_id: receiver.id})
        |> Messages.create_message()

      assert [message] == Messages.list_messages(%{filter: %{sender: sender.name}})

      assert [message] == Messages.list_messages(%{filter: %{receiver: receiver.name}})

      assert [message] == Messages.list_messages(%{filter: %{either: sender.phone}})

      assert [] == Messages.list_messages(%{filter: %{either: "ABC"}})
      assert [] == Messages.list_messages(%{filter: %{sender: "ABC"}})
      assert [] == Messages.list_messages(%{filter: %{receiver: "ABC"}})
    end

    test "list_messages/1 with tags included filters" do
      message_tag = Fixtures.message_tag_fixture()
      message_tag_2 = Fixtures.message_tag_fixture()

      message = Messages.get_message!(message_tag.message_id)
      _message_2 = Messages.get_message!(message_tag_2.message_id)
      _message_3 = message_fixture()

      assert [message] ==
               Messages.list_messages(%{filter: %{tags_included: [message_tag.tag_id]}})

      # Search for multiple tags
      message_list =
        Messages.list_messages(%{
          filter: %{tags_included: [message_tag.tag_id, message_tag_2.tag_id]}
        })

      assert length(message_list) == 2

      # Check if tag id is wrong, no message should be fetched
      [last_tag_id] =
        Glific.Tags.Tag
        |> order_by([t], desc: t.id)
        |> limit(1)
        |> select([t], t.id)
        |> Repo.all()

      wrong_tag_id = last_tag_id + 1

      message_list =
        Messages.list_messages(%{
          filter: %{tags_included: [wrong_tag_id]}
        })

      assert message_list == []
    end

    test "list_messages/1 with tags excluded filters" do
      message_tag = Fixtures.message_tag_fixture()
      message_tag_2 = Fixtures.message_tag_fixture()

      _message = Messages.get_message!(message_tag.message_id)
      _message_2 = Messages.get_message!(message_tag_2.message_id)
      _message_3 = message_fixture()

      message_list = Messages.list_messages(%{filter: %{tags_excluded: [message_tag.tag_id]}})
      assert length(message_list) == 2

      # Search for multiple tags
      message_list =
        Messages.list_messages(%{
          filter: %{tags_excluded: [message_tag.tag_id, message_tag_2.tag_id]}
        })

      assert length(message_list) == 1
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

    test "create_message/1 with valid data will set parent id if exists" do
      body = "Body for parent id"
      message1 = message_fixture()

      message_fixture(%{
        body: body,
        sender_id: message1.sender_id,
        receiver_id: message1.receiver_id
      })

      {:ok, message2} = Glific.Repo.fetch_by(Message, %{body: body})
      assert message1.id == message2.parent_id
    end

    test "create_message/1 with valid data will set ancestors id if exists" do
      message1 = message_fixture()

      message2 =
        message_fixture(%{sender_id: message1.sender_id, receiver_id: message1.receiver_id})

      message3 =
        message_fixture(%{sender_id: message1.sender_id, receiver_id: message1.receiver_id})

      message4 =
        message_fixture(%{sender_id: message1.sender_id, receiver_id: message1.receiver_id})

      message5 =
        message_fixture(%{sender_id: message1.sender_id, receiver_id: message1.receiver_id})

      body = "Body for ancestors message"

      message_fixture(%{
        body: body,
        sender_id: message1.sender_id,
        receiver_id: message1.receiver_id
      })

      {:ok, message6} = Glific.Repo.fetch_by(Message, %{body: body})
      assert message5.id == message6.parent_id
      assert length(message6.ancestors) == 5

      assert [message5.id, message4.id, message3.id, message2.id, message1.id] ==
               message6.ancestors
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

    test "create message with media type and without media id returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               @valid_attrs
               |> Map.merge(foreign_key_constraint())
               |> Map.merge(%{type: :image})
               |> Messages.create_message()
    end

    test "create and send message to multiple contacts should update the provider_message_id field in message" do
      default_organization_language = default_organization_language_fixture()

      {:ok, receiver_1} =
        @receiver_attrs
        |> Map.merge(%{phone: Phone.EnUs.phone(), language_id: default_organization_language.id})
        |> Contacts.create_contact()

      {:ok, receiver_2} =
        @receiver_attrs
        |> Map.merge(%{phone: Phone.EnUs.phone(), language_id: default_organization_language.id})
        |> Contacts.create_contact()

      contact_ids = [receiver_1.id, receiver_2.id]

      valid_attrs = %{
        body: "some body",
        flow: :outbound,
        type: :text
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint())

      [message1, message2 | _] =
        Messages.create_and_send_message_to_contacts(message_attrs, contact_ids)

      assert_enqueued(worker: Worker)
      Oban.drain_queue(:gupshup)

      message1 = Messages.get_message!(message1.id)
      message2 = Messages.get_message!(message2.id)

      assert message1.provider_message_id != nil
      assert message1.provider_status == :enqueued
      assert message1.flow == :outbound
      assert message1.sent_at != nil
      assert message2.provider_message_id != nil
      assert message2.provider_status == :enqueued
      assert message2.flow == :outbound
      assert message2.sent_at != nil
    end
  end

  describe "message_media" do
    alias Glific.Messages.MessageMedia

    @valid_attrs %{
      caption: "some caption",
      source_url: "some source_url",
      thumbnail: "some thumbnail",
      url: "some url",
      provider_media_id: "some provider_media_id"
    }
    @update_attrs %{
      caption: "some updated caption",
      source_url: "some updated source_url",
      thumbnail: "some updated thumbnail",
      url: "some updated url",
      provider_media_id: "some updated provider_media_id"
    }
    @invalid_attrs %{
      caption: nil,
      source_url: nil,
      thumbnail: nil,
      url: nil,
      provider_media_id: nil
    }

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

    test "count_messages_media/0 returns count of all message media" do
      _ = message_media_fixture()
      assert Messages.count_messages_media() == 1
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
      assert message_media.provider_media_id == "some provider_media_id"
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
      assert message_media.provider_media_id == "some updated provider_media_id"
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
