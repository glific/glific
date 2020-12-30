defmodule Glific.MessagesTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Faker.Phone

  alias Glific.{
    Contacts,
    Fixtures,
    Groups.Group,
    Messages,
    Messages.Message,
    Messages.MessageMedia,
    Repo,
    Seeds.SeedsDev,
    Tags.Tag,
    Templates.SessionTemplate
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_contacts(organization)
    :ok
  end

  describe "messages" do
    alias Glific.Providers.Gupshup.Worker

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
      optout_time: nil,
      phone: "12345671",
      last_message_at: DateTime.utc_now()
    }

    @receiver_attrs %{
      name: "some receiver",
      optin_time: DateTime.utc_now(),
      optout_time: nil,
      phone: "101013131",
      bsp_status: :session_and_hsm,
      last_message_at: DateTime.utc_now()
    }

    @valid_attrs %{
      body: "some body",
      flow: :inbound,
      type: :text,
      bsp_message_id: "some bsp_message_id",
      bsp_status: :enqueued
    }
    @update_attrs %{
      body: "some updated body",
      flow: :inbound,
      type: :text,
      bsp_message_id: "some updated bsp_message_id"
    }

    @invalid_attrs %{body: nil, flow: nil, type: nil, bsp_message_id: nil}

    defp foreign_key_constraint(attrs) do
      {:ok, sender} =
        @sender_attrs
        |> Map.merge(attrs)
        |> Map.merge(%{phone: Phone.EnUs.phone()})
        |> Contacts.create_contact()

      {:ok, receiver} =
        @receiver_attrs
        |> Map.merge(attrs)
        |> Map.merge(%{phone: Phone.EnUs.phone()})
        |> Contacts.create_contact()

      %{sender_id: sender.id, receiver_id: receiver.id, organization_id: sender.organization_id}
    end

    def message_fixture(attrs) do
      valid_attrs = Map.merge(@valid_attrs, foreign_key_constraint(attrs))

      {:ok, message} =
        valid_attrs
        |> Map.merge(attrs)
        |> Messages.create_message()

      # we do this to get the session_uuid which is computed by a trigger
      Messages.get_message!(message.id)
    end

    test "list_messages/1 returns all messages", attrs do
      message = message_fixture(attrs)
      assert Messages.list_messages(%{filter: attrs}) == [message]
    end

    test "list_messages/1 with multiple messages filtered", attrs do
      message = message_fixture(attrs)

      assert [message] ==
               Messages.list_messages(%{
                 opts: %{order: :asc},
                 filter: Map.merge(attrs, %{body: message.body})
               })

      assert [message] ==
               Messages.list_messages(%{
                 opts: %{order: :asc},
                 filter: Map.merge(attrs, %{bsp_status: message.bsp_status})
               })
    end

    test "count_messages/1 returns count of all messages", attrs do
      _ = message_fixture(attrs)
      assert Messages.count_messages(%{filter: attrs}) == 1

      assert Messages.count_messages(%{filter: Map.merge(attrs, %{body: "some body"})}) == 1
    end

    test "list_messages/1 with foreign key filters", attrs do
      {:ok, sender} = Contacts.create_contact(Map.merge(attrs, @sender_attrs))
      {:ok, receiver} = Contacts.create_contact(Map.merge(attrs, @receiver_attrs))

      {:ok, message} =
        @valid_attrs
        |> Map.merge(%{
          sender_id: sender.id,
          receiver_id: receiver.id,
          organization_id: sender.organization_id
        })
        |> Messages.create_message()

      # we do this to get the session_uuid which is computed by a trigger
      message = Messages.get_message!(message.id)

      assert [message] ==
               Messages.list_messages(%{filter: Map.merge(attrs, %{sender: sender.name})})

      assert [message] ==
               Messages.list_messages(%{filter: Map.merge(attrs, %{receiver: receiver.name})})

      assert [message] ==
               Messages.list_messages(%{filter: Map.merge(attrs, %{either: sender.phone})})

      oid = sender.organization_id

      assert [] == Messages.list_messages(%{filter: %{either: "ABC", organization_id: oid}})
      assert [] == Messages.list_messages(%{filter: %{sender: "ABC", organization_id: oid}})
      assert [] == Messages.list_messages(%{filter: %{receiver: "ABC", organization_id: oid}})
    end

    test "list_messages/1 with tags included filters",
         %{organization_id: organization_id} = attrs do
      message_tag = Fixtures.message_tag_fixture(attrs)
      message_tag_2 = Fixtures.message_tag_fixture(attrs)

      message = Messages.get_message!(message_tag.message_id)
      _message_2 = Messages.get_message!(message_tag_2.message_id)
      _message_3 = message_fixture(attrs)

      assert [message] ==
               Messages.list_messages(%{
                 filter: %{tags_included: [message_tag.tag_id], organization_id: organization_id}
               })

      # Search for multiple tags
      message_list =
        Messages.list_messages(%{
          filter: %{
            tags_included: [message_tag.tag_id, message_tag_2.tag_id],
            organization_id: organization_id
          }
        })

      assert length(message_list) == 2

      # Check if tag id is wrong, no message should be fetched
      [last_tag_id] =
        Tag
        |> order_by([t], desc: t.id)
        |> limit(1)
        |> select([t], t.id)
        |> Repo.all()

      wrong_tag_id = last_tag_id + 1

      message_list =
        Messages.list_messages(%{
          filter: %{
            tags_included: [wrong_tag_id],
            organization_id: organization_id
          }
        })

      assert message_list == []
    end

    test "list_messages/1 with tags excluded filters",
         %{organization_id: organization_id} = attrs do
      message_tag = Fixtures.message_tag_fixture(attrs)
      message_tag_2 = Fixtures.message_tag_fixture(attrs)

      _message = Messages.get_message!(message_tag.message_id)
      _message_2 = Messages.get_message!(message_tag_2.message_id)
      _message_3 = message_fixture(attrs)

      message_list =
        Messages.list_messages(%{
          filter: %{tags_excluded: [message_tag.tag_id], organization_id: organization_id}
        })

      assert length(message_list) == 2

      # Search for multiple tags
      message_list =
        Messages.list_messages(%{
          filter: %{
            tags_excluded: [message_tag.tag_id, message_tag_2.tag_id],
            organization_id: organization_id
          }
        })

      assert length(message_list) == 1
    end

    test "get_message!/1 returns the message with given id", attrs do
      message = message_fixture(attrs)
      assert Messages.get_message!(message.id) == message
    end

    test "create_message/1 with valid data creates a message", attrs do
      assert {:ok, %Message{} = message} =
               @valid_attrs
               |> Map.merge(foreign_key_constraint(attrs))
               |> Messages.create_message()
    end

    test "create_message/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Messages.create_message(@invalid_attrs)
    end

    test "create_message/1 with valid data will have the message number for the same contact",
         %{organization_id: organization_id} do
      message1 =
        message_fixture(%{
          body: "message 1",
          organization_id: organization_id
        })

      message_fixture(%{
        body: "message 2",
        sender_id: message1.sender_id,
        receiver_id: message1.receiver_id,
        organization_id: organization_id
      })

      message_fixture(%{
        body: "message 3",
        sender_id: message1.sender_id,
        receiver_id: message1.receiver_id,
        organization_id: organization_id
      })

      message_fixture(%{
        body: "message 4",
        sender_id: message1.sender_id,
        receiver_id: message1.receiver_id,
        organization_id: organization_id
      })

      message_fixture(%{
        body: "message 5",
        sender_id: message1.sender_id,
        receiver_id: message1.receiver_id,
        organization_id: organization_id
      })

      message_fixture(%{
        body: "message 6",
        sender_id: message1.sender_id,
        receiver_id: message1.receiver_id,
        organization_id: organization_id
      })

      {:ok, message6} =
        Repo.fetch_by(Message, %{body: "message 6", organization_id: organization_id})

      {:ok, message5} =
        Repo.fetch_by(Message, %{body: "message 5", organization_id: organization_id})

      {:ok, message4} =
        Repo.fetch_by(Message, %{body: "message 4", organization_id: organization_id})

      {:ok, message3} =
        Repo.fetch_by(Message, %{body: "message 3", organization_id: organization_id})

      {:ok, message2} =
        Repo.fetch_by(Message, %{body: "message 2", organization_id: organization_id})

      {:ok, message1} =
        Repo.fetch_by(Message, %{body: "message 1", organization_id: organization_id})

      assert message6.message_number == 0
      assert message5.message_number == 1
      assert message4.message_number == 2
      assert message3.message_number == 3
      assert message2.message_number == 4
      assert message1.message_number == 5
    end

    test "update_message/2 with valid data updates the message", attrs do
      message = message_fixture(attrs)
      assert {:ok, %Message{} = message} = Messages.update_message(message, @update_attrs)
    end

    test "update_message/2 with invalid data returns error changeset", attrs do
      message = message_fixture(attrs)
      assert {:error, %Ecto.Changeset{}} = Messages.update_message(message, @invalid_attrs)
      assert message == Messages.get_message!(message.id)
    end

    test "delete_message/1 deletes the message", attrs do
      message = message_fixture(attrs)
      assert {:ok, %Message{}} = Messages.delete_message(message)
      assert_raise Ecto.NoResultsError, fn -> Messages.get_message!(message.id) end
    end

    test "clear_messages/1 deletes all the messages of a contact", attrs do
      {:ok, message_media} =
        Messages.create_message_media(%{
          caption: "some caption",
          source_url: "some source_url",
          thumbnail: "some thumbnail",
          url: "some url",
          provider_media_id: "some provider_media_id",
          organization_id: attrs.organization_id
        })

      message = message_fixture(attrs |> Map.merge(%{media_id: message_media.id}))
      message = message |> Repo.preload(:contact)
      assert {:ok} = Messages.clear_messages(message.contact)

      assert {:error, ["Elixir.Glific.Messages.Message", "Resource not found"]} =
               Repo.fetch_by(Message, %{
                 contact_id: message.contact_id,
                 organization_id: message.organization_id
               })

      # message media should be deleted
      assert {:error, _} = Repo.fetch(MessageMedia, message_media.id)
    end

    test "change_message/1 returns a message changeset", attrs do
      message = message_fixture(attrs)
      assert %Ecto.Changeset{} = Messages.change_message(message)
    end

    test "create message with media type and without media id returns error changeset", attrs do
      assert {:error, %Ecto.Changeset{}} =
               @valid_attrs
               |> Map.merge(foreign_key_constraint(attrs))
               |> Map.merge(%{type: :image})
               |> Messages.create_message()
    end

    test "create and send message to multiple contacts should update the bsp_message_id field in message",
         %{organization_id: organization_id, global_schema: global_schema} = attrs do
      {:ok, receiver_1} =
        Contacts.create_contact(
          @receiver_attrs
          |> Map.merge(%{phone: Phone.EnUs.phone(), organization_id: organization_id})
        )

      {:ok, receiver_2} =
        Contacts.create_contact(
          @receiver_attrs
          |> Map.merge(%{phone: Phone.EnUs.phone(), organization_id: organization_id})
        )

      contact_ids = [receiver_1.id, receiver_2.id]

      valid_attrs = %{
        body: "some body",
        flow: :outbound,
        type: :text
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))

      assert {:ok, [contact1_id, contact2_id | _]} =
               Messages.create_and_send_message_to_contacts(message_attrs, contact_ids)

      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)

      assert {:ok, message1} =
               Repo.fetch_by(Message, %{
                 contact_id: contact1_id,
                 message_number: 0,
                 body: valid_attrs.body
               })

      assert {:ok, message2} =
               Repo.fetch_by(Message, %{
                 contact_id: contact2_id,
                 message_number: 0,
                 body: valid_attrs.body
               })

      assert message1.bsp_message_id != nil
      assert message1.bsp_status == :enqueued
      assert message1.flow == :outbound
      assert message1.sent_at != nil
      assert message2.bsp_message_id != nil
      assert message2.bsp_status == :enqueued
      assert message2.flow == :outbound
      assert message2.sent_at != nil
    end

    test "create and send message to multiple contacts should not send message to a contact with none bsp_status",
         %{organization_id: organization_id} = attrs do
      {:ok, receiver} =
        Contacts.create_contact(
          @receiver_attrs
          |> Map.merge(%{
            phone: Phone.EnUs.phone(),
            organization_id: organization_id,
            bsp_status: :none
          })
        )

      valid_attrs = %{
        body: "test message",
        flow: :outbound,
        type: :text
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))

      assert {:ok, []} =
               Messages.create_and_send_message_to_contacts(message_attrs, [receiver.id])
    end

    test "create and send message to a group should send message to contacts of the group",
         %{organization_id: organization_id} = attrs do
      [cg1 | _] = Fixtures.group_contacts_fixture(attrs)
      {:ok, group} = Repo.fetch_by(Group, %{id: cg1.group_id, organization_id: organization_id})
      group = group |> Repo.preload(:contacts)

      contact_ids =
        group.contacts
        |> Enum.map(fn contact -> contact.id end)

      valid_attrs = %{
        body: "test message",
        flow: :outbound,
        type: :text
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))

      assert {:ok, [contact1_id, contact2_id | _]} =
               Messages.create_and_send_message_to_group(message_attrs, group)

      # message should be sent only to the contacts of the group
      assert [contact1_id, contact2_id] -- contact_ids == []

      # a message should be created with group_id
      assert {:ok, _message} =
               Repo.fetch_by(Message, %{body: valid_attrs.body, group_id: group.id})

      # group should be updated with last communication at
      {:ok, updated_group} =
        Repo.fetch_by(Group, %{id: cg1.group_id, organization_id: organization_id})

      assert updated_group.last_communication_at >= group.last_communication_at
    end

    test "send hsm message incorrect parameters",
         %{organization_id: organization_id, global_schema: global_schema} = attrs do
      contact = Fixtures.contact_fixture(attrs)

      shortcode = "otp"

      {:ok, hsm_template} =
        Repo.fetch_by(
          SessionTemplate,
          %{shortcode: shortcode, organization_id: organization_id}
        )

      # Incorrect number of parameters should give an error
      parameters = ["param1"]

      {:error, error_message} =
        Messages.create_and_send_hsm_message(hsm_template.id, contact.id, parameters)

      assert error_message == "You need to provide correct number of parameters for hsm template"

      # Correct number of parameters should create and send hsm message
      parameters = ["param1", "param2", "param3"]

      {:ok, message} =
        Messages.create_and_send_hsm_message(hsm_template.id, contact.id, parameters)

      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)

      message = Messages.get_message!(message.id)

      assert message.is_hsm == true
      assert message.flow == :outbound
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.sent_at != nil
    end

    test "send media hsm message",
         %{organization_id: organization_id, global_schema: global_schema} = attrs do
      SeedsDev.seed_session_templates()
      contact = Fixtures.contact_fixture(attrs)

      shortcode = "account_update"

      {:ok, hsm_template} =
        Repo.fetch_by(
          SessionTemplate,
          %{shortcode: shortcode, organization_id: organization_id}
        )

      parameters = ["param1", "param2", "param3"]

      # send media hsm without media should return error
      {:error, error_message} =
        Messages.create_and_send_hsm_message(hsm_template.id, contact.id, parameters)

      assert error_message == "You need to provide media for media hsm template"

      media = SeedsDev.seed_messages_media()

      {:ok, message} =
        Messages.create_and_send_hsm_message(hsm_template.id, contact.id, parameters, media.id)

      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)

      message = Messages.get_message!(message.id)

      assert message.is_hsm == true
      assert message.flow == :outbound
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.sent_at != nil
    end

    test "prepare hsm template",
         %{organization_id: organization_id} do
      shortcode = "otp"

      {:ok, hsm_template} =
        Repo.fetch_by(
          SessionTemplate,
          %{shortcode: shortcode, organization_id: organization_id}
        )

      parameters = ["param1", "param2", "param3"]

      updated_hsm_template = Messages.parse_template_vars(hsm_template, parameters)

      assert updated_hsm_template.body ==
               "Your OTP for param1 is param2. This is valid for param3."
    end
  end

  describe "message_media" do
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

    test "list_messages_media/0 returns all message_media", attrs do
      message_media = message_media_fixture(%{organization_id: attrs.organization_id})
      assert Messages.list_messages_media() == [message_media]
    end

    test "count_messages_media/0 returns count of all message media", attrs do
      _ = message_media_fixture(%{organization_id: attrs.organization_id})
      assert Messages.count_messages_media() == 1
    end

    test "get_message_media!/1 returns the message_media with given id", attrs do
      message_media = message_media_fixture(%{organization_id: attrs.organization_id})
      assert Messages.get_message_media!(message_media.id) == message_media
    end

    test "create_message_media/1 with valid data creates a message_media", attrs do
      assert {:ok, %MessageMedia{} = message_media} =
               Messages.create_message_media(
                 @valid_attrs
                 |> Map.merge(%{organization_id: attrs.organization_id})
               )

      assert message_media.caption == "some caption"
      assert message_media.source_url == "some source_url"
      assert message_media.thumbnail == "some thumbnail"
      assert message_media.url == "some url"
      assert message_media.provider_media_id == "some provider_media_id"
    end

    test "create_message_media/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Messages.create_message_media(@invalid_attrs)
    end

    test "update_message_media/2 with valid data updates the message_media", attrs do
      message_media = message_media_fixture(%{organization_id: attrs.organization_id})

      assert {:ok, %MessageMedia{} = message_media} =
               Messages.update_message_media(message_media, @update_attrs)

      assert message_media.caption == "some updated caption"
      assert message_media.source_url == "some updated source_url"
      assert message_media.thumbnail == "some updated thumbnail"
      assert message_media.url == "some updated url"
      assert message_media.provider_media_id == "some updated provider_media_id"
    end

    test "update_message_media/2 with invalid data returns error changeset", attrs do
      message_media = message_media_fixture(%{organization_id: attrs.organization_id})

      assert {:error, %Ecto.Changeset{}} =
               Messages.update_message_media(message_media, @invalid_attrs)

      assert message_media == Messages.get_message_media!(message_media.id)
    end

    test "delete_message_media/1 deletes the message_media", attrs do
      message_media = message_media_fixture(%{organization_id: attrs.organization_id})
      assert {:ok, %MessageMedia{}} = Messages.delete_message_media(message_media)
      assert_raise Ecto.NoResultsError, fn -> Messages.get_message_media!(message_media.id) end
    end

    test "change_message_media/1 returns a message_media changeset", attrs do
      message_media = message_media_fixture(%{organization_id: attrs.organization_id})
      assert %Ecto.Changeset{} = Messages.change_message_media(message_media)
    end
  end
end
