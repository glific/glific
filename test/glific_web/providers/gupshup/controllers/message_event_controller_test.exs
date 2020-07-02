defmodule GlificWeb.Providers.Gupshup.Controllers.MessageEventControllerTest do
  use GlificWeb.ConnCase

  @message_event_request_params %{
    "app" => "Glific App",
    "payload" => %{
      "destination" => "1234567851",
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
    default_provider = Glific.SeedsDev.seed_providers()
    Glific.SeedsDev.seed_organizations(default_provider)
    Glific.SeedsDev.seed_contacts()
    Glific.SeedsDev.seed_messages()
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
      gupshup_id = Faker.String.base64(36)

      message_params =
        @message_event_request_params
        |> put_in(["payload", "type"], "enqueued")
        |> put_in(["payload", "id"], Faker.String.base64(36))
        |> put_in(["payload", "gsId"], gupshup_id)
        |> put_in(["payload", "payload"], %{"ts" => "1592311836"})

      [message | _] = Glific.Messages.list_messages()
      Glific.Messages.update_message(message, %{provider_message_id: gupshup_id})
      %{message_params: message_params, message: message}
    end

    test "enqueued status should update the message status", setup_config = %{conn: conn} do
      # when message enqueued
      conn = post(conn, "/gupshup", setup_config.message_params)
      json_response(conn, 200)
      message = Glific.Messages.get_message!(setup_config.message.id)
      assert message.provider_status == :enqueued

      # when message failed
      message_params = put_in(setup_config.message_params, ["payload", "type"], "failed")
      conn = post(conn, "/gupshup", message_params)
      json_response(conn, 200)
      message = Glific.Messages.get_message!(setup_config.message.id)
      assert message.provider_status == :error

      # when message sent
      message_params = put_in(setup_config.message_params, ["payload", "type"], "sent")
      conn = post(conn, "/gupshup", message_params)
      json_response(conn, 200)
      message = Glific.Messages.get_message!(setup_config.message.id)
      assert message.provider_status == :sent

      # when message read
      message_params = put_in(setup_config.message_params, ["payload", "type"], "read")
      conn = post(conn, "/gupshup", message_params)
      json_response(conn, 200)
      message = Glific.Messages.get_message!(setup_config.message.id)
      assert message.provider_status == :read

      # when message delivered
      message_params = put_in(setup_config.message_params, ["payload", "type"], "delivered")
      conn = post(conn, "/gupshup", message_params)
      json_response(conn, 200)
      message = Glific.Messages.get_message!(setup_config.message.id)
      assert message.provider_status == :delivered
    end
  end
end
