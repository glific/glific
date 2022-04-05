defmodule GlificWeb.Providers.Gupshup.Enterprise.Controllers.MessageEventControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Contacts,
    Messages,
    Seeds.SeedsDev
  }

  @message_event_request_params %{
    "cause" => "SUCCESS",
    "channel" => "WHATSAPP",
    "destAddr" => "1592311836",
    "eventTs" => 1_592_311_836,
    "eventType" => "DELIVERED",
    "srcAddr" => "SMSGupShup"
    "errorCode" => "000",
    "externalId" => "4610068946528501829-110609119085101347",
   }
  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  describe "handler" do
    test "handler should return nil data", %{conn: conn} do
      conn = post(conn, "/gupshup-enterprise", %{"response" = Jason.encode!(@message_event_request_params)
      assert json_response(conn, 200) == nil
      IO.inspect("asdf")
    end
  end

  describe "status" do
    setup %{conn: conn} do
      gupshup_id = Faker.String.base64(36)

      message_params =
        @message_event_request_params
        |> put_in(["payload", "eventType"], "DELIVERED")
        |> put_in(["payload", "externalId"], gupshup_id)
        |> put_in(["payload", "destAddr"], "1592311836")

      [message | _] =
        Messages.list_messages(%{filter: %{organization_id: conn.assigns[:organization_id]}})

      Messages.update_message(message, %{bsp_message_id: gupshup_id})
      %{message_params: message_params, message: message}
    end

    test "enqueued status should update the message status", setup_config = %{conn: conn} do

      # when message sent
      message_params = put_in(setup_config.message_params, ["payload", "type"], "sent")
      sent_conn = post(conn, "/gupshup", message_params)
      json_response(sent_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :sent

      # when message delivered
      message_params = put_in(setup_config.message_params, ["payload", "type"], "delivered")
      delivered_conn = post(conn, "/gupshup", message_params)
      json_response(delivered_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :delivered

      # when message failed with no code
      message_params = put_in(setup_config.message_params, ["payload", "type"], "failed")
      failed_conn = post(conn, "/gupshup", message_params)
      json_response(failed_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :error
      assert message.errors != nil
      assert message.errors != %{}

      # when message failed with code 1002 (bad phone number)
      message_params =
        setup_config.message_params
        |> put_in(["payload", "type"], "failed")
        |> put_in(["payload", "payload"], %{"ts" => "1592311836", "code" => 1002})

      failed_conn = post(conn, "/gupshup", message_params)
      json_response(failed_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :error
      assert message.errors != nil
      assert message.errors != %{}

      contact = Contacts.get_contact!(message.contact_id)
      assert contact.status == :invalid
      assert contact.optout_method == "Number does not exist"
    end
  end
end
