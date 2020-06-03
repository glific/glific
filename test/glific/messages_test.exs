defmodule Glific.MessagesTest do
  use Glific.DataCase

  alias Glific.Messages

  describe "messages" do
    alias Glific.Messages.Message
    alias Glific.Contacts

    @sender_attrs %{ name: "some sender",optin_time: ~U[2010-04-17 14:00:00Z],optout_time: ~U[2010-04-17 14:00:00Z],phone: "some sender phone",status: :valid,wa_id: "some sender wa_id",wa_status: :invalid}

    @recipient_attrs %{ name: "some recipient",optin_time: ~U[2010-04-17 14:00:00Z],optout_time: ~U[2010-04-17 14:00:00Z],phone: "some recipient phone",status: :valid,wa_id: "some recepient wa_id",wa_status: :invalid}


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

    # def setup do
    #   {:ok, sender} = Contacts.create_contact(%{ name: "some sender",optin_time: ~U[2010-04-17 14:00:00Z],optout_time: ~U[2010-04-17 14:00:00Z],phone: "some sender phone",status: :valid,wa_id: "some sender wa_id",wa_status: :invalid})
    #   {:ok, recipient} = Contacts.create_contact(%{ name: "some recipient",optin_time: ~U[2010-04-17 14:00:00Z],optout_time: ~U[2010-04-17 14:00:00Z],phone: "some recipient phone",status: :valid,wa_id: "some recepient wa_id",wa_status: :invalid})
    #   Map.merge(@valid_attrs, %{sender_id: sender.id, recipient_id: recipient.id, })
    # end

    defp forign_key_constraint() do
      {:ok, sender} = Contacts.create_contact(@sender_attrs)
      {:ok, recipient} = Contacts.create_contact(@recipient_attrs)
      %{sender_id: sender.id, recipient_id: recipient.id}
    end

    def message_fixture(attrs \\ %{}) do
      {:ok, message} =
        attrs
        |> Map.merge(forign_key_constraint())
        |> Enum.into(@valid_attrs)
        |> Messages.create_message()

      message
    end

    test "list_messages/0 returns all messages" do
      message = message_fixture()
      assert Messages.list_messages() == [message]
    end

    test "get_message!/1 returns the message with given id" do
      message = message_fixture()
      assert Messages.get_message!(message.id) == message
    end

    test "create_message/1 with valid data creates a message" do
      assert {:ok, %Message{} = message} =
        @valid_attrs
        |> Map.merge(forign_key_constraint())
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
end
