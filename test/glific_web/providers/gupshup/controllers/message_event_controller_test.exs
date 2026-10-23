defmodule GlificWeb.Providers.Gupshup.Controllers.MessageEventControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Contacts,
    Fixtures,
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

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  describe "handler" do
    test "handler should return nil data", %{conn: conn} do
      conn = post(conn, "/gupshup", @message_event_request_params)
      assert response(conn, 200) == ""
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
      # when message enqueued
      success_conn = post(conn, "/gupshup", setup_config.message_params)
      response(success_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :enqueued

      # when message sent
      message_params = put_in(setup_config.message_params, ["payload", "type"], "sent")
      sent_conn = post(conn, "/gupshup", message_params)
      response(sent_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :sent

      # when message read
      message_params = put_in(setup_config.message_params, ["payload", "type"], "read")
      read_conn = post(conn, "/gupshup", message_params)
      response(read_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :read

      # when message delivered
      message_params = put_in(setup_config.message_params, ["payload", "type"], "delivered")
      delivered_conn = post(conn, "/gupshup", message_params)
      response(delivered_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :delivered

      # when message failed with no code
      message_params = put_in(setup_config.message_params, ["payload", "type"], "failed")
      failed_conn = post(conn, "/gupshup", message_params)
      response(failed_conn, 200)
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
      response(failed_conn, 200)
      message = Messages.get_message!(setup_config.message.id)
      assert message.bsp_status == :error
      assert message.errors != nil
      assert message.errors != %{}

      contact = Contacts.get_contact!(message.contact_id)
      assert contact.status == :invalid
      assert contact.optout_method == "Number does not exist"
    end
  end

  describe "meta statuses" do
    setup do
      gupshup_id = Ecto.UUID.generate()

      {:ok, message} =
        %{bsp_message_id: gupshup_id}
        |> Fixtures.message_fixture()
        |> Messages.update_message(%{bsp_status: :error})

      %{message: message, gupshup_id: gupshup_id}
    end

    for {meta_status, bsp_status} <- [
          {"enqueued", :enqueued},
          {"sent", :sent},
          {"delivered", :delivered},
          {"read", :read}
        ] do
      test "#{meta_status} status sets bsp_status to #{bsp_status}",
           %{conn: conn, message: message, gupshup_id: gupshup_id} do
        payload = meta_status_payload(%{"gs_id" => gupshup_id, "status" => unquote(meta_status)})

        conn = post(conn, "/gupshup", payload)
        assert response(conn, 200) == ""
        assert Messages.get_message!(message.id).bsp_status == unquote(bsp_status)
      end
    end

    test "falls back to id when gs_id is missing",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      payload = meta_status_payload(%{"id" => gupshup_id, "status" => "delivered"})

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == :delivered
    end

    test "updates every status in a batched callback",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      other_gupshup_id = Ecto.UUID.generate()
      other_message = Fixtures.message_fixture(%{bsp_message_id: other_gupshup_id})

      payload =
        meta_status_payload([
          %{"gs_id" => gupshup_id, "status" => "read"},
          %{"gs_id" => other_gupshup_id, "status" => "delivered"}
        ])

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == :read
      assert Messages.get_message!(other_message.id).bsp_status == :delivered
    end

    test "failed status marks the message as error and keeps the error code",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      {:ok, message} = Messages.update_message(message, %{bsp_status: :sent, errors: %{}})

      payload =
        meta_status_payload(%{
          "gs_id" => gupshup_id,
          "status" => "failed",
          "errors" => [
            %{
              "code" => 131_049,
              "title" =>
                "This message was not delivered to maintain healthy ecosystem engagement."
            }
          ]
        })

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""

      message = Messages.get_message!(message.id)
      assert message.bsp_status == :error
      assert get_in(message.errors, ["payload", "payload", "code"]) == 131_049
      assert [%{"code" => 131_049}] = message.errors["errors"]
    end

    test "failed status with code 1002 marks the contact invalid",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      payload =
        meta_status_payload(%{
          "gs_id" => gupshup_id,
          "status" => "failed",
          "errors" => [%{"code" => 1002, "title" => "Number does not exist on WhatsApp"}]
        })

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""

      contact = Contacts.get_contact!(message.contact_id)
      assert contact.status == :invalid
    end

    test "failed status with top-level code and reason marks the contact invalid",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      payload =
        meta_status_payload(%{
          "gs_id" => gupshup_id,
          "status" => "failed",
          "code" => "1002",
          "reason" => "Number does not exist on WhatsApp"
        })

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""

      message = Messages.get_message!(message.id)
      assert get_in(message.errors, ["payload", "payload", "code"]) == 1002

      assert get_in(message.errors, ["payload", "payload", "reason"]) ==
               "Number does not exist on WhatsApp"

      contact = Contacts.get_contact!(message.contact_id)
      assert contact.status == :invalid
    end

    test "unknown status leaves the message untouched",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      payload = meta_status_payload(%{"gs_id" => gupshup_id, "status" => "deleted"})

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == message.bsp_status
    end

    test "status without a message id is skipped",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      payload =
        meta_status_payload([
          %{"status" => "read"},
          %{"gs_id" => gupshup_id, "status" => "read"}
        ])

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == :read
    end

    test "entry payload with an empty statuses list leaves the message untouched",
         %{conn: conn, message: message} do
      payload = meta_status_payload([])

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == message.bsp_status
    end

    test "inactive organization does not update the status",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      organization = Partners.organization(conn.assigns[:organization_id])
      {:ok, _organization} = Partners.update_organization(organization, %{status: :suspended})

      payload = meta_status_payload(%{"gs_id" => gupshup_id, "status" => "read"})

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == message.bsp_status
    end
  end

  defp meta_status_payload(statuses) do
    statuses =
      statuses
      |> List.wrap()
      |> Enum.map(
        &Map.merge(%{"recipient_id" => "917834811114", "timestamp" => 1_791_897_501_505}, &1)
      )

    %{
      "object" => "whatsapp_business_account",
      "entry" => [
        %{
          "id" => "1234567890",
          "changes" => [
            %{
              "field" => "messages",
              "value" => %{"messaging_product" => "whatsapp", "statuses" => statuses}
            }
          ]
        }
      ]
    }
  end
end
