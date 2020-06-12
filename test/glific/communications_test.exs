defmodule Glific.CommunicationsTest do
  use Glific.DataCase, async: true
  use Oban.Testing, repo: Glific.Repo

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
      optout_time: ~U[2010-04-17 14:00:00Z],
      phone: "12345671",
      status: :valid,
      provider_status: :invalid
    }

    @receiver_attrs %{
      name: "some receiver",
      optin_time: ~U[2010-04-17 14:00:00Z],
      optout_time: ~U[2010-04-17 14:00:00Z],
      phone: "101013131",
      status: :valid,
      provider_status: :invalid
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
      valid_attrs = Map.merge(@valid_attrs, foreign_key_constraint())

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

    test "sending media message without media object should be handled " do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 400,
            body: "error occured"
          }
      end)

      message = message_fixture(%{type: :image})
      Communications.send_message(message)
      message = Messages.get_message!(message.id)
      assert message.provider_message_id == nil
      assert message.provider_status == :error
      assert message.flow == :outbound
    end
  end
end
