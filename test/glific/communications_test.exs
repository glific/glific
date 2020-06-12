defmodule Glific.CommunicationsTest do
  use Glific.DataCase, async: true
  use Oban.Testing, repo: Glific.Repo
  alias Glific.Providers.Mock.Worker, as: Worker
  alias Glific.Messages

  describe "messages" do

    alias Glific.Communications.Message, as: Communications

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

    defp foreign_key_constraint do
      {:ok, sender} = Glific.Contacts.create_contact(@sender_attrs)
      {:ok, receiver} = Glific.Contacts.create_contact(@receiver_attrs)
      %{sender_id: sender.id, receiver_id: receiver.id}
    end

    def message_fixture(attrs \\ %{}) do
      valid_attrs = Map.merge(@valid_attrs, foreign_key_constraint())

      {:ok, message} =
        valid_attrs
        |> Map.merge(attrs)
        |> Messages.create_message()

      message
      |> Glific.Repo.preload([:receiver, :sender, :media])
    end

    test "send message should update the message id" do
      message = message_fixture()
      Communications.send_message(message)
      assert_enqueued worker: Worker
      Oban.drain_queue(:mock)
      message = Messages.get_message!(message.id)
      assert message.provider_message_id != nil
      assert message.provider_status == :enqueued
      assert message.flow == :outbound
    end
  end

end
