defmodule GlificWeb.Providers.Gupshup.Enterprise.Controllers.MessageEventControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Messages,
    Seeds.SeedsDev
  }

  @message_event_request_params %{
    "cause" => "SUCCESS",
    "channel" => "WHATSAPP",
    "destAddr" => "1592311836",
    "eventTs" => 1_592_311_836,
    "eventType" => "DELIVERED",
    "srcAddr" => "SMSGupShup",
    "errorCode" => "000",
    "externalId" => "4610068946528501829-110609119085101347"
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
      message = %{"response" => Jason.encode!([@message_event_request_params])}
      conn = post(conn, "/gupshup-enterprise-enterprise", message)
      assert json_response(conn, 200) == nil
    end
  end

  describe "status" do
    setup %{conn: conn} do
      gupshup_id = Faker.String.base64(36)

      message_params =
        @message_event_request_params
        |> put_in(["eventType"], "DELIVERED")
        |> put_in(["externalId"], gupshup_id)
        |> put_in(["destAddr"], "1592311836")

      [message | _] =
        Messages.list_messages(%{filter: %{organization_id: conn.assigns[:organization_id]}})

      Messages.update_message(message, %{bsp_message_id: gupshup_id})
      %{message_params: message_params, message: message}
    end

    test "enqueued status should update the message status", setup_config = %{conn: conn} do
      # when message sent
      message_params =
        put_in(setup_config.message_params, ["eventType"], "SENT")
        |> then(&%{"response" => Jason.encode!([&1])})

      sent_conn = post(conn, "/gupshup-enterprise", message_params)
      json_response(sent_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :sent

      # when message delivered
      message_params =
        put_in(setup_config.message_params, ["eventType"], "DELIVERED")
        |> then(&%{"response" => Jason.encode!([&1])})

      delivered_conn = post(conn, "/gupshup-enterprise", message_params)
      json_response(delivered_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :delivered

      # when message failed with no code
      message_params =
        put_in(setup_config.message_params, ["eventType"], "READ")
        |> then(&%{"response" => Jason.encode!([&1])})

      failed_conn = post(conn, "/gupshup-enterprise", message_params)
      json_response(failed_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :read
    end
  end
end
