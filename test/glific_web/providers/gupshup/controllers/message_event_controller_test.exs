defmodule GlificWeb.Providers.Gupshup.Controllers.MessageEventControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Messages,
    Partners,
    Seeds.SeedsDev
  }

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

  defp get_params(conn, default_params) do
    organization = Partners.organization(conn.assigns[:organization_id])
    app_name = organization.services["bsp"].secrets["app_name"]
    Map.merge(default_params, %{"app" => app_name})
  end

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  describe "handler" do
    test "handler should return nil data", %{conn: conn} do
      params = get_params(conn, @message_event_request_params)
      conn = post(conn, "/gupshup", params)
      assert json_response(conn, 200) == nil
    end
  end

  describe "status" do
    setup %{conn: conn} do
      gupshup_id = Faker.String.base64(36)

      message_params =
        @message_event_request_params
        |> put_in(["payload", "type"], "enqueued")
        |> put_in(["payload", "id"], Faker.String.base64(36))
        |> put_in(["payload", "gsId"], gupshup_id)
        |> put_in(["payload", "payload"], %{"ts" => "1592311836"})

      [message | _] =
        Messages.list_messages(%{filter: %{organization_id: conn.assigns[:organization_id]}})

      Messages.update_message(message, %{bsp_message_id: gupshup_id})
      %{message_params: message_params, message: message}
    end

    test "enqueued status should update the message status", setup_config = %{conn: conn} do
      params = get_params(conn, setup_config.message_params)
      # when message enqueued
      success_conn = post(conn, "/gupshup", params)
      json_response(success_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :enqueued

      # when message failed
      message_params = put_in(setup_config.message_params, ["payload", "type"], "failed")
      params = get_params(conn, message_params)
      failed_conn = post(conn, "/gupshup", params)
      json_response(failed_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :error
      assert message.errors != nil
      assert message.errors != %{}

      # when message sent
      message_params = put_in(setup_config.message_params, ["payload", "type"], "sent")
      params = get_params(conn, message_params)
      sent_conn = post(conn, "/gupshup", params)
      json_response(sent_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :sent

      # when message read
      message_params = put_in(setup_config.message_params, ["payload", "type"], "read")
      params = get_params(conn, message_params)
      read_conn = post(conn, "/gupshup", params)
      json_response(read_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :read

      # when message delivered
      message_params = put_in(setup_config.message_params, ["payload", "type"], "delivered")
      params = get_params(conn, message_params)
      delivered_conn = post(conn, "/gupshup", params)
      json_response(delivered_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :delivered
    end
  end
end
