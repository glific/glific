defmodule Glific.CommunicationsTest do
  use Glific.DataCase, async: true
  use Oban.Testing, repo: Glific.Repo

  alias Faker.Phone
  alias Glific.Messages

  describe "communications" do
    alias Glific.Communications

    test "fetch default provider" do
      Application.put_env(:glific, :provider, nil)
      assert Glific.Providers.Gupshup == Communications.effective_provider()
    end

    test "fetch provider from config" do
      Application.put_env(:glific, :provider, Glific.Providers.Gupshup)
      assert Glific.Providers.Gupshup == Communications.effective_provider()
    end
  end

  describe "gupshup_messages" do
    alias Glific.Communications.Message, as: Communications
    alias Glific.Providers.Gupshup.Worker, as: Worker

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
      last_message_at: DateTime.utc_now()
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
      provider_media_id: "some provider_media_id"
    }

    defp foreign_key_constraint do
      {:ok, sender} = Glific.Contacts.create_contact(@sender_attrs)
      {:ok, receiver} = Glific.Contacts.create_contact(@receiver_attrs)
      %{sender_id: sender.id, receiver_id: receiver.id}
    end

    defp message_fixture(attrs \\ %{}) do
      valid_attrs = Map.merge(foreign_key_constraint(), @valid_attrs)

      {:ok, message} =
        valid_attrs
        |> Map.merge(attrs)
        |> Messages.create_message()

      message
      |> Glific.Repo.preload([:receiver, :sender, :media])
    end

    defp message_media_fixture(attrs \\ %{}) do
      {:ok, message_media} =
        attrs
        |> Enum.into(@valid_media_attrs)
        |> Messages.create_message_media()

      message_media
    end

    test "send message should update the provider message id" do
      message = message_fixture()
      Communications.send_message(message)
      assert_enqueued(worker: Worker)
      Oban.drain_queue(:gupshup)
      message = Messages.get_message!(message.id)
      assert message.provider_message_id != nil
      assert message.sent_at != nil
      assert message.provider_status == :enqueued
      assert message.flow == :outbound
    end

    test "if response status code is not 200 handle the error response " do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 400,
            body: "Error"
          }
      end)

      message = message_fixture()
      Communications.send_message(message)
      assert_enqueued(worker: Worker)
      Oban.drain_queue(:gupshup)
      message = Messages.get_message!(message.id)
      assert message.provider_message_id == nil
      assert message.provider_status == :error
      assert message.flow == :outbound
      assert message.sent_at == nil
    end

    test "send media message should update the provider message id" do
      message_media = message_media_fixture()

      # image message
      message = message_fixture(%{type: :image, media_id: message_media.id})
      Communications.send_message(message)
      assert_enqueued(worker: Worker)
      Oban.drain_queue(:gupshup)
      message = Messages.get_message!(message.id)
      assert message.provider_message_id != nil
      assert message.provider_status == :enqueued
      assert message.flow == :outbound
      assert message.sent_at != nil

      # audio message
      {:ok, message} =
        Messages.update_message(message, %{type: :audio, media_id: message_media.id})

      message = Glific.Repo.preload(message, [:receiver, :sender, :media])
      Communications.send_message(message)
      assert_enqueued(worker: Worker)
      Oban.drain_queue(:gupshup)
      message = Messages.get_message!(message.id)
      assert message.provider_message_id != nil
      assert message.provider_status == :enqueued
      assert message.flow == :outbound

      # video message
      {:ok, message} =
        Messages.update_message(message, %{type: :video, media_id: message_media.id})

      message = Glific.Repo.preload(message, [:receiver, :sender, :media])
      Communications.send_message(message)
      assert_enqueued(worker: Worker)
      Oban.drain_queue(:gupshup)
      message = Messages.get_message!(message.id)
      assert message.provider_message_id != nil
      assert message.provider_status == :enqueued
      assert message.flow == :outbound

      # document message
      {:ok, message} =
        Messages.update_message(message, %{type: :document, media_id: message_media.id})

      message = Glific.Repo.preload(message, [:receiver, :sender, :media])
      Communications.send_message(message)
      assert_enqueued(worker: Worker)
      Oban.drain_queue(:gupshup)
      message = Messages.get_message!(message.id)
      assert message.provider_message_id != nil
      assert message.provider_status == :enqueued
      assert message.flow == :outbound
    end

    test "sending message to contact having invalid status will return error" do
      {:ok, receiver} =
        @receiver_attrs
        |> Map.merge(%{status: :invalid, phone: Phone.EnUs.phone()})
        |> Glific.Contacts.create_contact()

      message = message_fixture(%{receiver_id: receiver.id})
      assert {:error, _msg} = Communications.send_message(message)
    end

    test "sending message to contact having invalid provider status will return error" do
      {:ok, receiver} =
        @receiver_attrs
        |> Map.merge(%{provider_status: :invalid, phone: Phone.EnUs.phone()})
        |> Glific.Contacts.create_contact()

      message = message_fixture(%{receiver_id: receiver.id})
      assert {:error, _msg} = Communications.send_message(message)
    end

    test "sending message if last received message is more then 24 hours returns error" do
      {:ok, receiver} =
        @receiver_attrs
        |> Map.merge(%{
          phone: Phone.EnUs.phone(),
          last_message_at: Timex.shift(DateTime.utc_now(), days: -2)
        })
        |> Glific.Contacts.create_contact()

      message = message_fixture(%{receiver_id: receiver.id})
      assert {:error, _msg} = Communications.send_message(message)

    test "update_provider_status/2 will update the message status based on provider message ID" do
      message =
        message_fixture(%{
          provider_message_id: Faker.String.base64(36),
          provider_status: :enqueued
        })

      Communications.update_provider_status(message.provider_message_id, :read)
      message = Messages.get_message!(message.id)
      assert message.provider_status == :read
    end
  end
end
