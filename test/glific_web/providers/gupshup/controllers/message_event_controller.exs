defmodule GlificWeb.MessageEventControllerTest do
  use GlificWeb.ConnCase

  alias Glific.Messages.Message

  @message_event_request_params %{
    "app" => "Glific App",
    "payload" => %{
      "destination" => "919917443994",
      "gsId" => "853bab23-0963-42c7-8436-7fe4f5866c76",
      "id" => "gBEGkZkXRDmUAgl5FpzpjNgI5Co",
      "payload" => %{
        "ts" => 1_592_311_836
      }
    },
    "timestamp" => 1_592_311_842_070,
    "type" => "message-event",
    "version" => 2
  }

  setup do
    Glific.Seeds.seed_contacts()
    Glific.Seeds.seed_messages()
    :ok
  end

  describe "handler" do
    test "handler should return nil data", %{conn: conn} do
      conn = post(conn, "/gupshup", @message_event_request_params)
      assert json_response(conn, 200) == nil
    end
  end

  describe "status" do
    setup do
      message_payload = %{
        "ts" => "1592311836"
      }

      message_params =
        @message_request_params
        |> put_in(["payload", "type"], "enqueued")
        |> put_in(["payload", "id"], Faker.String.base64(36))
        |> put_in(["payload", "gsId"], Faker.String.base64(36))
        |> put_in(["payload", "payload"], message_payload)

      %{message_params: message_params}
    end

    test "enqueued status should update the message status", setup_config = %{conn: conn} do
      provider_message_id = get_in(setup_config.message_params, ["payload", "gsId"])
      {:ok, message} = Glific.Repo.fetch_by(Message, %{body: "Default message body"})
      Glific.Messages.update_message(message, %{provider_message_id: provider_message_id})
      conn = post(conn, "/gupshup", setup_config.message_params)
      json_response(conn, 200)

      {:ok, message} = Glific.Messages.get_message!(message.id)

      assert message.provider_status == :enqueued
    end

    test "read status should update the message status", setup_config = %{conn: conn} do
      provider_message_id = get_in(setup_config.message_params, ["payload", "gsId"])
      {:ok, message} = Glific.Repo.fetch_by(Message, %{body: "Default message body"})
      Glific.Messages.update_message(message, %{provider_message_id: provider_message_id})

      message_params = put_in(setup_config.message_params, ["payload", "type"], "read")
      conn = post(conn, "/gupshup", message_params)
      json_response(conn, 200)

      {:ok, message} = Glific.Messages.get_message!(message.id)
      assert message.provider_status == :read
    end
  end
end
