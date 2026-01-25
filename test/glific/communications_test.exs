defmodule Glific.CommunicationsTest do
  use Glific.DataCase, async: true
  use Oban.Testing, repo: Glific.Repo

  alias Faker.Phone

  alias Glific.{
    Communications,
    Contacts,
    Fixtures,
    Messages,
    Providers.Gupshup.Worker,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  describe "gupshup_messages" do
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
      phone: "12345671",
      last_message_at: DateTime.utc_now()
    }

    @receiver_attrs %{
      name: "some receiver",
      optin_time: ~U[2010-04-17 14:00:00Z],
      phone: "101013131",
      last_message_at: DateTime.utc_now(),
      bsp_status: :session_and_hsm
    }

    @valid_attrs %{
      body: "some body",
      flow: :outbound,
      type: :text
    }

    @valid_media_attrs %{
      caption: "some caption",
      source_url: "some source_url",
      thumbnail: "some thumbnail",
      url: "some url",
      flow: :outbound,
      is_template_media: false
    }

    defp foreign_key_constraint(attrs) do
      {:ok, sender} = Contacts.create_contact(Map.merge(attrs, @sender_attrs))
      {:ok, receiver} = Contacts.create_contact(Map.merge(attrs, @receiver_attrs))
      %{sender_id: sender.id, receiver_id: receiver.id, organization_id: receiver.organization_id}
    end

    defp message_fixture(attrs) do
      # eliminating bsp_status here since in this case, its meant for the
      # message and not the contact
      {_value, attrs} = Map.pop(attrs, :bsp_status)

      valid_attrs =
        Map.merge(
          foreign_key_constraint(attrs),
          @valid_attrs
        )

      {:ok, message} =
        valid_attrs
        |> Map.merge(attrs)
        |> Messages.create_message()

      message
      |> Repo.preload([:receiver, :sender, :media])
    end

    def message_media_fixture(attrs \\ %{}) do
      {:ok, message_media} =
        attrs
        |> Enum.into(@valid_media_attrs)
        |> Messages.create_message_media()

      message_media
    end

    test "send message should update the provider message id",
         %{global_schema: global_schema} = attrs do
      message = message_fixture(attrs)
      Communications.Message.send_message(message)
      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)
      message = Messages.get_message!(message.id)
      assert message.bsp_message_id != nil
      assert message.sent_at != nil
      assert message.bsp_status == :enqueued
      assert message.flow == :outbound
    end

    test "send message should return error when characters limit is reached when sending text message",
         attrs do
      message =
        attrs
        |> Map.merge(%{body: Faker.Lorem.sentence(4097)})
        |> message_fixture()

      {:error, error_msg} = Communications.Message.send_message(message)
      assert error_msg == "Message size greater than 4096 characters"
    end

    test "send message should return error when characters limit is reached when sending media message",
         attrs do
      message_media =
        message_media_fixture(%{
          caption: Faker.Lorem.sentence(4097),
          organization_id: attrs.organization_id
        })

      message =
        attrs
        |> Map.merge(%{type: :image, media_id: message_media.id})
        |> message_fixture()

      {:error, error_msg} = Communications.Message.send_message(message)
      assert error_msg == "Message size greater than 4096 characters"
    end

    test "send message will remove the Not replied tag from messages",
         %{organization_id: _organization_id, global_schema: global_schema} = attrs do
      message_1 = Fixtures.message_fixture(Map.merge(attrs, %{flow: :inbound}))

      message_2 =
        Fixtures.message_fixture(
          Map.merge(
            attrs,
            %{
              flow: :outbound,
              sender_id: message_1.sender_id,
              receiver_id: message_1.contact_id
            }
          )
        )

      assert message_2.contact_id == message_1.contact_id

      Communications.Message.send_message(message_2)
      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)

      contact_1 = Contacts.get_contact!(message_1.contact_id)
      assert contact_1.is_org_replied == true
    end

    test "if response status code is not 200 handle the error response",
         %{global_schema: global_schema} = attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 400,
            body: "Error"
          }
      end)

      message = message_fixture(attrs)
      Communications.Message.send_message(message)
      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)
      message = Messages.get_message!(message.id)
      assert message.bsp_message_id == nil
      assert message.bsp_status == :error
      assert message.flow == :outbound
      assert message.sent_at == nil
    end

    test "handle connection refused error when API call fails",
         %{global_schema: global_schema} = attrs do
      Tesla.Mock.mock(fn
        %{method: :post} -> {:error, :connrefused}
      end)

      message = message_fixture(attrs)
      Communications.Message.send_message(message)
      assert_enqueued(worker: Worker, prefix: global_schema)

      # To verify the error is handled
      assert %{success: 1, cancelled: 0, discard: 0, failure: 0, snoozed: 0} =
               Oban.drain_queue(queue: :gupshup)

      message = Messages.get_message!(message.id)
      assert message.bsp_message_id == nil
      assert message.bsp_status == :error
      assert message.flow == :outbound
      assert message.sent_at == nil
    end

    test "handle connection timeout error when API call fails",
         %{global_schema: global_schema} = attrs do
      Tesla.Mock.mock(fn
        %{method: :post} -> {:error, :timeout}
      end)

      message = message_fixture(attrs)
      Communications.Message.send_message(message)
      assert_enqueued(worker: Worker, prefix: global_schema)

      # Job should fail since it returns {:error, _} due to which Oban retries 1 more time
      assert %{success: 0, cancelled: 0, discard: 0, failure: 1, snoozed: 0} =
               Oban.drain_queue(queue: :gupshup)

      message = Messages.get_message!(message.id)
      assert message.bsp_message_id == nil
      assert message.bsp_status == :error
      assert message.flow == :outbound
      assert message.sent_at == nil
      assert %{"payload" => %{"payload" => %{"error" => "{:error, :timeout}"}}} = message.errors
    end

    test "send media message should update the provider message id",
         %{global_schema: global_schema} = attrs do
      message_media = message_media_fixture(%{organization_id: attrs.organization_id})

      # image message
      message =
        message_fixture(
          Map.merge(
            attrs,
            %{type: :image, media_id: message_media.id}
          )
        )

      Communications.Message.send_message(message)
      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)
      message = Messages.get_message!(message.id)
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.flow == :outbound
      assert message.sent_at != nil

      # audio message
      {:ok, message} =
        Messages.update_message(message, %{type: :audio, media_id: message_media.id})

      message = Repo.preload(message, [:receiver, :sender, :media])
      Communications.Message.send_message(message)
      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)
      message = Messages.get_message!(message.id)
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.flow == :outbound

      # video message
      {:ok, message} =
        Messages.update_message(message, %{type: :video, media_id: message_media.id})

      message = Repo.preload(message, [:receiver, :sender, :media])
      Communications.Message.send_message(message)
      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)
      message = Messages.get_message!(message.id)
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.flow == :outbound

      # document message
      {:ok, message} =
        Messages.update_message(message, %{type: :document, media_id: message_media.id})

      message = Repo.preload(message, [:receiver, :sender, :media])
      Communications.Message.send_message(message)
      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)
      message = Messages.get_message!(message.id)
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.flow == :outbound

      # sticker message
      {:ok, message} =
        Messages.update_message(message, %{type: :sticker, media_id: message_media.id})

      Communications.Message.send_message(message)
      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)
      message = Messages.get_message!(message.id)
      assert message.bsp_message_id != nil
      assert message.bsp_status == :enqueued
      assert message.flow == :outbound
      assert message.sent_at != nil
    end

    test "sending message to optout contact will return error", attrs do
      {:ok, receiver} =
        @receiver_attrs
        |> Map.merge(%{status: :invalid, phone: Phone.EnUs.phone()})
        |> Map.merge(attrs)
        |> Contacts.create_contact()

      attrs = Map.merge(attrs, %{receiver_id: receiver.id})
      assert {:error, _msg} = Messages.create_and_send_message(attrs)
    end

    test "sending message to contact having incorrect provider status will return error", attrs do
      {:ok, receiver} =
        @receiver_attrs
        |> Map.merge(%{bsp_status: :none, phone: Phone.EnUs.phone()})
        |> Map.merge(attrs)
        |> Contacts.create_contact()

      attrs = Map.merge(attrs, %{receiver_id: receiver.id})
      assert {:error, _msg} = Messages.create_and_send_message(attrs)
    end

    test "sending message if last received message is more then 24 hours returns error", attrs do
      {:ok, receiver} =
        @receiver_attrs
        |> Map.merge(%{
          phone: Phone.EnUs.phone(),
          last_message_at: Timex.shift(DateTime.utc_now(), days: -2),
          bsp_status: :none
        })
        |> Map.merge(attrs)
        |> Contacts.create_contact()

      attrs = Map.merge(attrs, %{receiver_id: receiver.id})
      assert {:error, _msg} = Messages.create_and_send_message(attrs)
    end

    test "update_bsp_status/2 will update the message status based on provider message ID",
         attrs do
      message =
        message_fixture(
          Map.merge(
            attrs,
            %{
              bsp_message_id: Faker.String.base64(36),
              bsp_status: :enqueued
            }
          )
        )

      Communications.Message.update_bsp_status(message.bsp_message_id, :read, nil)
      message = Messages.get_message!(message.id)
      assert message.bsp_status == :read
    end

    test "send message at a specific time should not send it immediately",
         %{global_schema: global_schema} = attrs do
      scheduled_time = Timex.shift(DateTime.utc_now(), hours: 2)

      message =
        %{send_at: scheduled_time}
        |> Map.merge(attrs)
        |> message_fixture()

      Communications.Message.send_message(message)

      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)
      message = Messages.get_message!(message.id)

      assert message.status == :enqueued
      assert message.bsp_message_id == nil
      assert message.sent_at == nil
      assert message.bsp_status == nil
      assert message.flow == :outbound

      # Verify job scheduled
      assert_enqueued(
        worker: Worker,
        scheduled_at: {scheduled_time, delta: 10},
        prefix: global_schema
      )
    end

    test "send message to simulator will be process normally",
         %{global_schema: global_schema, organization_id: _organization_id} = _attrs do
      simulator_phone = Contacts.simulator_phone_prefix() <> "_1"
      {:ok, simulator} = Repo.fetch_by(Contacts.Contact, %{phone: simulator_phone})

      message = Fixtures.message_fixture(%{receiver_id: simulator.id})
      {:ok, msg} = Communications.Message.send_message(message)
      assert_enqueued(worker: Worker, prefix: global_schema)
      Oban.drain_queue(queue: :gupshup)
      sent_msg = Messages.get_message!(msg.id)
      assert sent_msg.errors == %{}
    end
  end

  test "send message in high tps queue if flag enabled for the org",
       %{global_schema: global_schema} = attrs do
    FunWithFlags.enable(:high_trigger_tps_enabled,
      for_actor: %{organization_id: attrs.organization_id}
    )

    scheduled_time = Timex.shift(DateTime.utc_now(), hours: 2)

    message =
      %{send_at: scheduled_time}
      |> Map.merge(attrs)
      |> message_fixture()

    Communications.Message.send_message(message)

    message = Messages.get_message!(message.id)

    assert message.status == :enqueued
    assert message.bsp_message_id == nil
    assert message.sent_at == nil
    assert message.bsp_status == nil
    assert message.flow == :outbound

    # Verify job scheduled in correct queue
    refute_enqueued(
      queue: :gupshup,
      worker: Worker,
      prefix: global_schema
    )

    assert_enqueued(
      queue: :gupshup_high_tps,
      worker: Worker,
      prefix: global_schema
    )

    FunWithFlags.disable(:high_trigger_tps_enabled,
      for_actor: %{organization_id: attrs.organization_id}
    )
  end

  describe "mailer" do
    alias Swoosh.Email
    import Swoosh.TestAssertions

    alias Glific.{
      Fixtures,
      Mails.BalanceAlertMail,
      Mails.MailLog,
      Mails.NewPartnerOnboardedMail,
      Mails.NotificationMail,
      Partners
    }

    test "send/2 will deliver a mail based on given args", attrs do
      mail_attrs = %{category: "test", organization_id: attrs.organization_id}
      email = Email.new(subject: "Hello, Glific Team!", from: Communications.Mailer.sender())
      Communications.Mailer.send(email, mail_attrs)
      assert_email_sent(email)

      assert MailLog.count_mail_logs(%{
               filter: Map.merge(attrs, %{category: "test"})
             }) == 1
    end

    test "NotificationMail mail struct sends the critical notification mail", attrs do
      mail_attrs = %{category: "critical_notification", organization_id: attrs.organization_id}
      notification = Fixtures.notification_fixture(%{organization_id: attrs.organization_id})

      critical_notification_mail =
        Partners.organization(notification.organization_id)
        |> NotificationMail.critical_mail(notification.message)

      assert {:ok, _} = Communications.Mailer.send(critical_notification_mail, mail_attrs)

      assert_email_sent(critical_notification_mail)

      assert MailLog.count_mail_logs(%{
               filter: Map.merge(attrs, %{category: "critical_notification"})
             }) == 1
    end

    test "NewPartnerOnboardedMail mail struct sends the onboard notification mail", attrs do
      mail_attrs = %{category: "new_partner_onboarded", organization_id: attrs.organization_id}

      new_partner_onboarded_email =
        Partners.organization(attrs.organization_id)
        |> NewPartnerOnboardedMail.new_mail()

      assert {:ok, _} = Communications.Mailer.send(new_partner_onboarded_email, mail_attrs)

      assert_email_sent(new_partner_onboarded_email)

      assert MailLog.count_mail_logs(%{
               filter: Map.merge(attrs, %{category: "new_partner_onboarded"})
             }) == 1
    end

    test "BalanceAlertMail mail struct sends the low balance mail", attrs do
      mail_attrs = %{category: "low_bsp_balance", organization_id: attrs.organization_id}

      low_balance_email =
        Partners.organization(attrs.organization_id)
        |> BalanceAlertMail.low_balance_alert(2.5)

      assert {:ok, _} = Communications.Mailer.send(low_balance_email, mail_attrs)

      assert_email_sent(low_balance_email)

      assert MailLog.count_mail_logs(%{
               filter: Map.merge(attrs, %{category: "low_bsp_balance"})
             }) == 1
    end
  end
end
