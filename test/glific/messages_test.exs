defmodule Glific.MessagesTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Faker.Phone

  alias Glific.{
    Contacts,
    Fixtures,
    Groups,
    Groups.Group,
    Messages,
    Messages.Message,
    Messages.MessageMedia,
    Partners,
    Repo,
    Seeds.SeedsDev,
    Tags.Tag,
    Templates.InteractiveTemplate,
    Templates.InteractiveTemplates,
    Templates.SessionTemplate,
    Users
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_contacts(organization)
    SeedsDev.hsm_templates(organization)
    SeedsDev.seed_users(organization)
    SeedsDev.seed_interactives(organization)
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

    # Update Gupshup Enterprise as default bsp
    defp enable_gupshup_enterprise(attrs) do
      updated_attrs = %{
        is_active: true,
        organization_id: attrs.organization_id,
        shortcode: "gupshup_enterprise"
      }

      {:ok, cred} =
        Partners.get_credential(%{
          organization_id: attrs.organization_id,
          shortcode: "gupshup_enterprise"
        })

      Partners.update_credential(cred, updated_attrs)
    end

    def message_fixture(attrs) do
      valid_attrs = Map.merge(@valid_attrs, foreign_key_constraint(attrs))

      {:ok, message} =
        valid_attrs
        |> Map.merge(attrs)
        |> Map.put(:bsp_message_id, Faker.String.base64(10))
        |> Messages.create_message()

      # we do this to get the session_uuid which is computed by a trigger
      Messages.get_message!(message.id)
    end

    test "list_messages/1 returns all messages", attrs do
      message = message_fixture(attrs)
      assert Messages.list_messages(%{filter: attrs}) == [message]
    end

    test "list_messages/1 returns all messages with types filter", attrs do
      message_fixture(Map.merge(attrs, %{type: :quick_reply}))
      message_fixture(Map.merge(attrs, %{type: :location}))
      message_fixture(Map.merge(attrs, %{type: :text}))
      message_fixture(Map.merge(attrs, %{type: :quick_reply}))
      message_fixture(Map.merge(attrs, %{type: :text}))

      assert length(Messages.list_messages(%{filter: %{types: [:quick_reply, :location]}})) == 3
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

      from_date = message.inserted_at |> DateTime.to_date()

      assert [message] ==
               Messages.list_messages(%{
                 opts: %{order: :asc},
                 filter: Map.merge(attrs, %{date_range: %{from: from_date}})
               })

      to_date = message.inserted_at |> DateTime.to_date() |> Date.add(2)

      assert [message] ==
               Messages.list_messages(%{
                 opts: %{order: :asc},
                 filter: Map.merge(attrs, %{date_range: %{to: to_date}})
               })

      assert [message] ==
               Messages.list_messages(%{
                 opts: %{order: :asc},
                 filter:
                   Map.merge(attrs, %{
                     date_range: %{from: from_date, to: to_date, column: "updated_at"}
                   })
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

    test "list_messages/1 with flow_id filters", attrs do
      {:ok, sender} = Contacts.create_contact(Map.merge(attrs, @sender_attrs))
      {:ok, receiver} = Contacts.create_contact(Map.merge(attrs, @receiver_attrs))
      flow = Fixtures.flow_fixture(attrs)

      {:ok, message} =
        @valid_attrs
        |> Map.merge(%{
          sender_id: sender.id,
          receiver_id: receiver.id,
          organization_id: sender.organization_id,
          flow_id: flow.id
        })
        |> Messages.create_message()

      # we do this to get the session_uuid which is computed by a trigger
      message = Messages.get_message!(message.id)

      assert [message] ==
               Messages.list_messages(%{filter: Map.merge(attrs, %{flow_id: flow.id})})

      assert [] ==
               Messages.list_messages(%{filter: Map.merge(attrs, %{flow_id: 999_999})})
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

    test "tag_in_message?/2 should check message has tag",
         %{organization_id: organization_id} = attrs do
      tag = Fixtures.tag_fixture(%{organization_id: organization_id})
      message = message_fixture(attrs)
      assert false == Messages.tag_in_message?(message, tag.id)
    end

    test "create_message/1 with valid data creates a message", attrs do
      assert {:ok, %Message{}} =
               @valid_attrs
               |> Map.merge(foreign_key_constraint(attrs))
               |> Messages.create_message()
    end

    test "create_message/1 with valid data and nil body creates a message", attrs do
      assert {:ok, message} =
               @valid_attrs
               |> Map.put(:body, nil)
               |> Map.merge(foreign_key_constraint(attrs))
               |> Messages.create_message()

      assert message.body == ""
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

      assert message6.message_number == 6
      assert message5.message_number == 5
      assert message4.message_number == 4
      assert message3.message_number == 3
      assert message2.message_number == 2
      assert message1.message_number == 1
    end

    test "update_message/2 with valid data updates the message", attrs do
      message = message_fixture(attrs)
      assert {:ok, %Message{}} = Messages.update_message(message, @update_attrs)
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
          flow: :inbound,
          is_template_media: false,
          organization_id: attrs.organization_id
        })

      message = message_fixture(attrs |> Map.merge(%{media_id: message_media.id}))
      message = message |> Repo.preload(:contact)
      assert :ok = Messages.clear_messages(message.contact)

      assert {:error, ["Elixir.Glific.Messages.Message", "Resource not found"]} =
               Repo.fetch_by(Message, %{
                 contact_id: message.contact_id,
                 organization_id: message.organization_id
               })

      # message media should be deleted
      assert {:error, _} = Repo.fetch(MessageMedia, message_media.id)
    end

    test "clear_messages/1 deletes messages for simulator and sends a message with default body",
         attrs do
      message = message_fixture(attrs)

      {:ok, contact} =
        Repo.fetch_by(Glific.Contacts.Contact, %{
          name: "Glific Simulator One",
          organization_id: message.organization_id
        })

      assert :ok = Messages.clear_messages(contact)

      {:ok, message} =
        Repo.fetch_by(Message, %{
          contact_id: contact.id,
          organization_id: contact.organization_id
        })

      message = Messages.get_message!(message.id)

      assert message.body == "Default message body"
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

    test "flow in the message_media should be outbound when we are sending message", attrs do
      message_media =
        message_media_fixture(%{
          caption: "image caption",
          organization_id: attrs.organization_id,
          flow: :outbound
        })

      valid_attrs = %{
        flow: :outbound,
        type: :image,
        media_id: message_media.id
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert message.type == :image
      assert is_nil(message.media_id) == false
      message_media = Messages.get_message_media!(message.media_id)
      assert message_media.flow == :outbound
    end

    test "variable will be replaced in media caption after creating a message", attrs do
      media =
        attrs
        |> Map.merge(%{caption: "Hello @contact.phone"})
        |> Fixtures.message_media_fixture()

      {:ok, message} =
        @valid_attrs
        |> Map.merge(foreign_key_constraint(attrs))
        |> Map.merge(%{type: :image, media_id: media.id})
        |> Messages.create_message()

      message_media = Messages.get_message_media!(media.id)

      receiver = Contacts.get_contact!(message.receiver_id)

      assert message_media.caption == "Hello #{receiver.phone}"
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
               Messages.create_and_send_message_to_contacts(message_attrs, contact_ids, :session)

      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)

      assert {:ok, message1} =
               Repo.fetch_by(Message, %{
                 contact_id: contact1_id,
                 message_number: 1,
                 body: valid_attrs.body
               })

      assert {:ok, message2} =
               Repo.fetch_by(Message, %{
                 contact_id: contact2_id,
                 message_number: 1,
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
               Messages.create_and_send_message_to_contacts(
                 message_attrs,
                 [receiver.id],
                 :session
               )
    end

    test "create_group_message/1 should create group message",
         %{organization_id: organization_id} do
      org_contact = Glific.Partners.organization(organization_id).contact

      valid_attrs = %{
        body: "group message",
        flow: :outbound,
        type: :text
      }

      message_attrs =
        Map.merge(valid_attrs, %{
          sender_id: org_contact.id,
          receiver_id: org_contact.id,
          organization_id: organization_id
        })

      assert {:ok, %Message{}} = Messages.create_group_message(message_attrs)
    end

    test "create_group_message/1 should create group message when send by staff member",
         %{organization_id: organization_id = _attrs} do
      [_u1, _u2, _u3, u4 | _] = Users.list_users(%{organization_id: organization_id})

      group_1 = Fixtures.group_fixture(%{label: "new group"})

      # add user groups
      :ok =
        Groups.update_user_groups(%{
          user_id: u4.id,
          group_ids: ["#{group_1.id}"],
          organization_id: u4.organization_id
        })

      {:ok, restricted_user} = Users.update_user(u4, %{is_restricted: true})
      admin_user = Repo.get_current_user()
      Repo.put_current_user(restricted_user)

      valid_attrs = %{
        body: "group message",
        flow: :outbound,
        type: :text,
        group_id: group_1.id
      }

      message_attrs =
        Map.merge(valid_attrs, %{
          sender_id: restricted_user.contact_id,
          organization_id: organization_id,
          user_id: restricted_user.id
        })

      assert {:ok, %Message{}} = Messages.create_group_message(message_attrs)
      Repo.put_current_user(admin_user)
    end

    test "create_group_message/1 should return changeset error", attrs do
      assert {:error, %Ecto.Changeset{}} =
               @invalid_attrs
               |> Map.merge(foreign_key_constraint(attrs))
               |> Messages.create_group_message()
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
      org_contact = Glific.Partners.organization(organization_id).contact

      assert {:ok, [contact1_id, contact2_id | _]} =
               Messages.create_and_send_message_to_group(message_attrs, group, :session)

      # message should be sent only to the contacts of the group
      assert [contact1_id, contact2_id] -- contact_ids == []

      # a message should be created with group_id
      assert {:ok, _message} =
               Repo.fetch_by(Message, %{
                 body: valid_attrs.body,
                 group_id: group.id,
                 sender_id: org_contact.id,
                 receiver_id: org_contact.id
               })

      # group should be updated with last communication at
      {:ok, updated_group} =
        Repo.fetch_by(Group, %{id: cg1.group_id, organization_id: organization_id})

      assert updated_group.last_communication_at >= group.last_communication_at
    end

    test "create and send message should send message to contact", attrs do
      valid_attrs = %{
        body: "test message",
        flow: :outbound,
        type: :text
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert message.body == "test message"

      # also ensure that we get an error when receiver is non existent
      message_attrs = Map.put(message_attrs, :receiver_id, 1_234_567)
      {:error, error} = Messages.create_and_send_message(message_attrs)
      assert error == "Receiver does not exist"
    end

    test "create and send message should send message to contact through gupshup enterprise",
         attrs do
      enable_gupshup_enterprise(attrs)

      valid_attrs = %{
        body: "test message",
        flow: :outbound,
        type: :text
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert message.body == "test message"
    end

    test "create and send message should send template message to contact through gupshup enterprise",
         attrs do
      enable_gupshup_enterprise(attrs)

      shortcode = "otp"

      {:ok, hsm_template} =
        Repo.fetch_by(
          SessionTemplate,
          %{shortcode: shortcode, organization_id: attrs.organization_id}
        )

      valid_attrs = %{
        body: hsm_template.example,
        flow: :outbound,
        is_hsm: true,
        params: ["adding Anil as a payee", "1234", "15 minutes"],
        template_id: hsm_template.id,
        type: :text
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)

      assert message.body ==
               "Your OTP for adding Anil as a payee is 1234. This is valid for 15 minutes."
    end

    test "create and send message should send image message to contact through gupshup enterprise",
         attrs do
      enable_gupshup_enterprise(attrs)

      message_media =
        message_media_fixture(%{
          caption: "image caption",
          organization_id: attrs.organization_id
        })

      valid_attrs = %{
        flow: :outbound,
        type: :image,
        media_id: message_media.id
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert message.type == :image
      assert is_nil(message.media_id) == false
    end

    test "create and send message should send video message to contact through gupshup enterprise",
         attrs do
      enable_gupshup_enterprise(attrs)

      message_media =
        message_media_fixture(%{
          caption: "video caption",
          organization_id: attrs.organization_id
        })

      valid_attrs = %{
        flow: :outbound,
        type: :video,
        media_id: message_media.id
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert message.type == :video
      assert is_nil(message.media_id) == false
    end

    test "create and send message should send file message to contact through gupshup enterprise",
         attrs do
      enable_gupshup_enterprise(attrs)

      message_media =
        message_media_fixture(%{
          caption: "file name",
          organization_id: attrs.organization_id
        })

      valid_attrs = %{
        flow: :outbound,
        type: :document,
        media_id: message_media.id
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert message.type == :document
      assert is_nil(message.media_id) == false
    end

    test "create and send message should send audio message to contact through gupshup enterprise",
         attrs do
      enable_gupshup_enterprise(attrs)

      message_media =
        message_media_fixture(%{
          organization_id: attrs.organization_id
        })

      valid_attrs = %{
        flow: :outbound,
        type: :audio,
        media_id: message_media.id
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert message.type == :audio
      assert is_nil(message.media_id) == false
    end

    test "create and send interactive message with type as location_request_message should send message",
         %{organization_id: organization_id} = attrs do
      label = "Send Location"

      {:ok, interactive_template} =
        Repo.fetch_by(
          InteractiveTemplate,
          %{label: label, organization_id: organization_id}
        )

      valid_attrs = %{
        body: nil,
        flow: :outbound,
        interactive_template_id: interactive_template.id,
        type: :location_request_message
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert false == is_nil(message.interactive_content)
      assert false == is_nil(message.interactive_template_id)
      assert message.body == "please share your location"
    end

    test "create and send message interactive quick reply message with image should have message body as image caption",
         %{organization_id: organization_id} = attrs do
      label = "Quick Reply Image"

      Glific.Fixtures.mock_validate_media()

      {:ok, interactive_template} =
        Repo.fetch_by(
          InteractiveTemplate,
          %{label: label, organization_id: organization_id}
        )

      valid_attrs = %{
        body: nil,
        flow: :outbound,
        interactive_template_id: interactive_template.id,
        type: :quick_reply
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert message.body == "body text"
      assert false == is_nil(message.media_id)
    end

    test "create and send message interactive quick reply message should have message body text",
         %{organization_id: organization_id} = attrs do
      label = "Quick Reply Text"

      {:ok, interactive_template} =
        Repo.fetch_by(
          InteractiveTemplate,
          %{label: label, organization_id: organization_id}
        )

      valid_attrs = %{
        body: nil,
        flow: :outbound,
        interactive_template_id: interactive_template.id,
        type: :quick_reply
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      msg_interactive_content = message.interactive_content
      assert message.body == "Glific is a two way communication platform"
      assert msg_interactive_content["content"]["header"] == "Quick Reply Text"
      # send interactive quick reply message with send_with_title as false
      InteractiveTemplates.update_interactive_template(interactive_template, %{
        send_with_title: false
      })

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert message.body == "Glific is a two way communication platform"
    end

    test "create and send message interactive quick reply message with document should have message body as ",
         %{organization_id: organization_id} = attrs do
      label = "Quick Reply Document"
      Glific.Fixtures.mock_validate_media("pdf")

      {:ok, interactive_template} =
        Repo.fetch_by(
          InteractiveTemplate,
          %{label: label, organization_id: organization_id}
        )

      valid_attrs = %{
        body: nil,
        flow: :outbound,
        interactive_template_id: interactive_template.id,
        type: :quick_reply
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert message.body == "http://enterprise.smsgupshup.com/doc/GatewayAPIDoc.pdf"
      assert false == is_nil(message.media_id)
    end

    test "create and send message interactive list message should have message body as list body",
         %{organization_id: organization_id} = attrs do
      label = "Interactive list"

      {:ok, interactive_template} =
        Repo.fetch_by(
          InteractiveTemplate,
          %{label: label, organization_id: organization_id}
        )

      valid_attrs = %{
        body: nil,
        flow: :outbound,
        interactive_template_id: interactive_template.id,
        type: :quick_reply
      }

      # send interactive list message with send_with_title as false
      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert message.body == "Glific"

      InteractiveTemplates.update_interactive_template(interactive_template, %{
        send_with_title: false
      })

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert message.body == "Glific"
    end

    test "create and send message should send message to contact with replacing global vars",
         attrs do
      Partners.get_organization!(attrs.organization_id)
      |> Partners.update_organization(%{fields: %{"org_name" => "Glific"}})

      valid_attrs = %{
        body: "test message from @global.org_name",
        flow: :outbound,
        type: :text
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:ok, message} = Messages.create_and_send_message(message_attrs)
      message = Messages.get_message!(message.id)
      assert message.body == "test message from Glific"
    end

    test "create and send message should send message to contact should return error", attrs do
      updated_attrs = %{
        is_active: false,
        organization_id: attrs.organization_id,
        shortcode: "gupshup"
      }

      {:ok, cred} =
        Partners.get_credential(%{organization_id: attrs.organization_id, shortcode: "gupshup"})

      Partners.update_credential(cred, updated_attrs)

      valid_attrs = %{
        body: "test message",
        flow: :outbound,
        type: :text
      }

      message_attrs = Map.merge(valid_attrs, foreign_key_constraint(attrs))
      {:error, message} = Messages.create_and_send_message(message_attrs)
      assert message == "Could not send message to contact: Check Gupshup Setting"
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
        %{template_id: hsm_template.id, receiver_id: contact.id, parameters: parameters}
        |> Messages.create_and_send_hsm_message()

      assert error_message == "Please provide the right number of parameters for the template."

      # Correct number of parameters should create and send hsm message
      parameters = ["param1", "param2", "param3"]

      {:ok, message} =
        %{template_id: hsm_template.id, receiver_id: contact.id, parameters: parameters}
        |> Messages.create_and_send_hsm_message()

      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)

      message = Messages.get_message!(message.id)

      assert message.is_hsm == true
      assert message.flow == :outbound
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.sent_at != nil

      # also send hsm message via the wrapper function
      {:ok, message} =
        %{
          template_id: hsm_template.id,
          receiver_id: contact.id,
          params: parameters,
          organization_id: organization_id,
          is_hsm: true
        }
        |> Messages.create_and_send_message()

      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)

      message = Messages.get_message!(message.id)

      assert message.is_hsm == true
      assert message.flow == :outbound
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.sent_at != nil
    end

    test "send button template message",
         %{organization_id: organization_id, global_schema: global_schema} = attrs do
      SeedsDev.seed_session_templates()
      contact = Fixtures.contact_fixture(attrs)
      shortcode = "account_balance"

      {:ok, hsm_template} =
        Repo.fetch_by(
          SessionTemplate,
          %{shortcode: shortcode, organization_id: organization_id}
        )

      parameters = ["param1"]

      # send hsm with buttons should send button template
      {:ok, message} =
        %{
          template_id: hsm_template.id,
          receiver_id: contact.id,
          parameters: parameters
        }
        |> Messages.create_and_send_hsm_message()

      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)

      message = Messages.get_message!(message.id)
      assert message.is_hsm == true

      assert message.body ==
               "You can now view your Account Balance or Mini statement for Account ending with param1 simply by selecting one of the options below.| [View Account Balance] | [View Mini Statement] "

      assert message.flow == :outbound
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.sent_at != nil

      # send hsm with buttons should send translated button template
      Contacts.update_contact(contact, %{language_id: 2})

      {:ok, message} =
        %{
          template_id: hsm_template.id,
          receiver_id: contact.id,
          parameters: parameters
        }
        |> Messages.create_and_send_hsm_message()

      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)

      message = Messages.get_message!(message.id)
      assert message.is_hsm == true

      assert message.body ==
               " अब आप नीचे दिए विकल्पों में से एक का चयन करके param1 के साथ समाप्त होने वाले खाते के लिए अपना खाता शेष या मिनी स्टेटमेंट देख सकते हैं। | [अकाउंट बैलेंस देखें] | [देखें मिनी स्टेटमेंट]"

      assert message.flow == :outbound
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.sent_at != nil
    end

    test "Params are formatted based on whatsApp rules",
         %{organization_id: organization_id, global_schema: global_schema} = attrs do
      SeedsDev.seed_session_templates()
      contact = Fixtures.contact_fixture(attrs)
      shortcode = "account_balance"

      {:ok, hsm_template} =
        Repo.fetch_by(
          SessionTemplate,
          %{shortcode: shortcode, organization_id: organization_id}
        )

      parameters = ["param          1\n"]

      # send hsm with buttons should send button template
      {:ok, message} =
        %{
          template_id: hsm_template.id,
          receiver_id: contact.id,
          parameters: parameters
        }
        |> Messages.create_and_send_hsm_message()

      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)

      message = Messages.get_message!(message.id)
      assert message.is_hsm == true

      assert message.body ==
               "You can now view your Account Balance or Mini statement for Account ending with param 1 simply by selecting one of the options below.| [View Account Balance] | [View Mini Statement] "

      assert message.flow == :outbound
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.sent_at != nil

      # send hsm with buttons should send translated button template
      Contacts.update_contact(contact, %{language_id: 2})

      {:ok, message} =
        %{
          template_id: hsm_template.id,
          receiver_id: contact.id,
          parameters: parameters
        }
        |> Messages.create_and_send_hsm_message()

      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)

      message = Messages.get_message!(message.id)
      assert message.is_hsm == true

      assert message.body ==
               " अब आप नीचे दिए विकल्पों में से एक का चयन करके param 1 के साथ समाप्त होने वाले खाते के लिए अपना खाता शेष या मिनी स्टेटमेंट देख सकते हैं। | [अकाउंट बैलेंस देखें] | [देखें मिनी स्टेटमेंट]"

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
        %{template_id: hsm_template.id, receiver_id: contact.id, parameters: parameters}
        |> Messages.create_and_send_hsm_message()

      assert error_message == "Please provide media for media template."

      media = Fixtures.message_media_fixture(attrs)

      # send media hsm with media should send media template
      {:ok, message} =
        %{
          template_id: hsm_template.id,
          receiver_id: contact.id,
          parameters: parameters,
          media_id: media.id
        }
        |> Messages.create_and_send_hsm_message()

      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)

      message = Messages.get_message!(message.id)

      assert message.is_hsm == true
      assert message.flow == :outbound
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.sent_at != nil

      # send media hsm with media should send video template
      parameters = ["anil"]

      {:ok, hsm_template} =
        Repo.fetch_by(
          SessionTemplate,
          %{shortcode: "file_update", organization_id: organization_id}
        )

      {:ok, message} =
        %{
          template_id: hsm_template.id,
          receiver_id: contact.id,
          parameters: parameters,
          media_id: media.id
        }
        |> Messages.create_and_send_hsm_message()

      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)

      message = Messages.get_message!(message.id)

      assert message.is_hsm == true
      assert message.flow == :outbound
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.sent_at != nil
    end

    test "send document hsm message",
         %{organization_id: organization_id, global_schema: global_schema} = attrs do
      SeedsDev.seed_session_templates()
      contact = Fixtures.contact_fixture(attrs)

      shortcode = "file_reminder"

      {:ok, hsm_template} =
        Repo.fetch_by(
          SessionTemplate,
          %{shortcode: shortcode, organization_id: organization_id}
        )

      parameters = ["param1"]

      # send media hsm without media should return error
      {:error, error_message} =
        %{template_id: hsm_template.id, receiver_id: contact.id, parameters: parameters}
        |> Messages.create_and_send_hsm_message()

      assert error_message == "Please provide media for media template."

      media = Fixtures.message_media_fixture(attrs)

      # send media hsm with media should send media template
      {:ok, message} =
        %{
          template_id: hsm_template.id,
          receiver_id: contact.id,
          parameters: parameters,
          media_id: media.id
        }
        |> Messages.create_and_send_hsm_message()

      assert_enqueued(worker: Worker, prefix: global_schema)
      assert %{success: 1} = Oban.drain_queue(queue: :gupshup, with_safety: false)

      message = Messages.get_message!(message.id)

      assert message.is_hsm == true
      assert message.flow == :outbound
      assert message.status == :sent
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
      flow: :inbound,
      is_template_media: false
    }
    @update_attrs %{
      caption: "some updated caption",
      source_url: "some updated source_url",
      thumbnail: "some updated thumbnail",
      url: "some updated url",
      is_template_media: false
    }
    @invalid_attrs %{
      caption: nil,
      source_url: nil,
      thumbnail: nil,
      url: nil,
      is_template_media: false
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

      assert {:ok, %MessageMedia{} = message_media} =
               Messages.create_message_media(
                 @valid_attrs
                 |> Map.merge(%{
                   organization_id: attrs.organization_id,
                   caption: "updated caption"
                 })
               )

      assert message_media.caption == "updated caption"
      assert message_media.source_url == "some source_url"
      assert message_media.thumbnail == "some thumbnail"
      assert message_media.url == "some url"
    end

    test "create_message_media/1 with invalid data returns error changeset", attrs do
      assert {:error, %Ecto.Changeset{}} =
               Map.merge(@invalid_attrs, %{organization_id: attrs.organization_id})
               |> Messages.create_message_media()
    end

    test "update_message_media/2 with valid data updates the message_media", attrs do
      message_media = message_media_fixture(%{organization_id: attrs.organization_id})

      assert {:ok, %MessageMedia{} = message_media} =
               Messages.update_message_media(message_media, @update_attrs)

      assert message_media.caption == "some updated caption"
      assert message_media.source_url == "some updated source_url"
      assert message_media.thumbnail == "some updated thumbnail"
      assert message_media.url == "some updated url"
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

    test "get_media_type_from_url/1 check the url and share the type", _attrs do
      media_types = [
        %{
          type: :image,
          url: "https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample01.jpg",
          content_type: "image/png"
        },
        %{
          type: :video,
          url: "https://www.buildquickbots.com/whatsapp/media/sample/video/sample01.mp4",
          content_type: "video/x-msvideo"
        },
        %{
          type: :audio,
          url: "https://www.buildquickbots.com/whatsapp/media/sample/audio/sample01.mp3",
          content_type: "audio/aac"
        },
        %{
          type: :document,
          url: "https://www.buildquickbots.com/whatsapp/media/sample/pdf/sample01.pdf",
          content_type: "application/pdf"
        }
      ]

      Enum.each(media_types, fn media_type ->
        Tesla.Mock.mock(fn
          %{method: :get} ->
            %Tesla.Env{
              headers: [
                {"content-type", media_type.content_type},
                {"content-length", "3209581"}
              ],
              method: :get,
              status: 200
            }
        end)

        assert {media_type.type, media_type.url} ==
                 Messages.get_media_type_from_url(media_type.url)
      end)

      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            headers: [
              {"content-type", "unknown"}
            ],
            method: :get,
            status: 200
          }
      end)

      assert {:text, nil} == Messages.get_media_type_from_url("any url")

      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            headers: [
              {"content-typess", "anthing"}
            ],
            method: :get,
            status: 400
          }
      end)

      assert {:text, nil} == Messages.get_media_type_from_url("any url")
    end

    test "validate media/2 check for nil or empty media url", _attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            headers: [
              {"content-type", "image/png"},
              {"content-length", "3209581"}
            ],
            method: :get,
            status: 200
          }
      end)

      assert %{is_valid: false, message: "Please provide a media URL"} ==
               Messages.validate_media(
                 "",
                 nil
               )

      assert %{is_valid: false, message: "Please provide a media URL"} ==
               Messages.validate_media(
                 nil,
                 nil
               )
    end

    # we suffix fix with ever increasing sizes to bypass the caching we've added
    @valid_media_url "https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample02.jpg"

    test "validate media/2 check for size error", _attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            headers: [
              {"content-type", "image/png"},
              {"content-length", "3209581222"}
            ],
            method: :get,
            status: 200
          }
      end)

      assert %{
               is_valid: false,
               message: "Size is too big for the image. Maximum size limit is 5120KB"
             } ==
               Messages.validate_media(
                 @valid_media_url <> "_1",
                 "image"
               )
    end

    test "validate media/2 check for invalid header", _attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            headers: [
              {"content-length", "3209581"}
            ],
            method: :get,
            status: 200
          }
      end)

      assert %{
               is_valid: false,
               message: "Media content-type is not valid"
             } ==
               Messages.validate_media(
                 @valid_media_url <> "_2",
                 "image"
               )
    end

    test "validate media/2 when media type and url are different", _attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            headers: [
              {"content-type", "image/png"},
              {"content-length", "3209581"}
            ],
            method: :get,
            status: 200
          }
      end)

      assert %{
               is_valid: false,
               message: "Media content-type is not valid"
             } ==
               Messages.validate_media(
                 @valid_media_url <> "_3",
                 "video"
               )
    end

    test "validate media/2 check for type other than defined default types", _attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            headers: [
              {"content-type", "image/png"},
              {"content-length", "3209581"}
            ],
            method: :get,
            status: 200
          }
      end)

      assert %{
               is_valid: false,
               message: "Media content-type is not valid"
             } ==
               Messages.validate_media(
                 @valid_media_url <> "_4",
                 "text"
               )
    end

    test "validate media/2 return valid as true", _attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            headers: [
              {"content-type", "image/png"},
              {"content-length", "3209581"}
            ],
            method: :get,
            status: 200
          }
      end)

      # we want this cached
      assert %{is_valid: true, message: "success"} ==
               Messages.validate_media(
                 @valid_media_url,
                 "image"
               )

      {:ok, value} = Glific.Caches.get_global({:validate_media, @valid_media_url, "image"})
      assert value == %{is_valid: true, message: "success"}

      # this time it should be fetching from the cache
      assert %{is_valid: true, message: "success"} ==
               Messages.validate_media(
                 @valid_media_url,
                 "image"
               )
    end

    @valid_audio_media_url "https://www.buildquickbots.com/whatsapp/media/sample/audio/sample02"

    test "validate media/2 check for ogg audio", _attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            headers: [
              {"content-type", "audio/ogg"},
              {"content-length", "3209581"}
            ],
            method: :get,
            status: 200
          }
      end)

      assert %{
               is_valid: false,
               message: "Media content-type is not valid"
             } ==
               Messages.validate_media(
                 @valid_audio_media_url <> ".ogg",
                 "audio"
               )
    end

    test "validate media/2 check for mp3 audio", _attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            headers: [
              {"content-type", "audio/mp3"},
              {"content-length", "3209581"}
            ],
            method: :get,
            status: 200
          }
      end)

      assert %{
               is_valid: true,
               message: "success"
             } ==
               Messages.validate_media(
                 @valid_audio_media_url <> ".mp3",
                 "audio"
               )
    end

    test "change_message_media/1 returns a message_media changeset", attrs do
      message_media = message_media_fixture(%{organization_id: attrs.organization_id})
      assert %Ecto.Changeset{} = Messages.change_message_media(message_media)
    end

    test "create_and_send_otp_session_message/2 should send the correct session otp message",
         attrs do
      contact = Fixtures.contact_fixture(attrs)
      otp = "112233"
      {:ok, %Message{} = message} = Messages.create_and_send_otp_session_message(contact, otp)

      assert message.body ==
               "112233 is your verification code. For your security, do not share this code."
    end
  end
end
