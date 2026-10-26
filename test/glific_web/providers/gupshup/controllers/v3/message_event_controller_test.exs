defmodule GlificWeb.Providers.Gupshup.Controllers.V3.MessageEventControllerTest do
  use GlificWeb.ConnCase

  alias Glific.Contacts
  alias Glific.Fixtures
  alias Glific.Messages
  alias Glific.Partners
  alias Glific.Seeds.SeedsDev

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
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

    test "failed status with a Meta error code is recorded without contact side effects",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      contact_status = Contacts.get_contact!(message.contact_id).status

      payload =
        meta_status_payload(%{
          "gs_id" => gupshup_id,
          "status" => "failed",
          "errors" => [%{"code" => 131_026, "title" => "Message undeliverable"}]
        })

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""

      message = Messages.get_message!(message.id)
      assert message.bsp_status == :error
      assert get_in(message.errors, ["payload", "payload", "code"]) == 131_026
      assert Contacts.get_contact!(message.contact_id).status == contact_status
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

    test "failed status keeps a non-numeric error code as is",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      payload =
        meta_status_payload(%{
          "gs_id" => gupshup_id,
          "status" => "failed",
          "code" => "E_UNKNOWN",
          "reason" => "Unknown error"
        })

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""

      message = Messages.get_message!(message.id)
      assert get_in(message.errors, ["payload", "payload", "code"]) == "E_UNKNOWN"
    end

    test "status without a status field leaves the message untouched",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      payload = meta_status_payload(%{"gs_id" => gupshup_id})

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == message.bsp_status
    end

    test "entry without changes is routed to the unknown handler",
         %{conn: conn, message: message} do
      payload = %{"object" => "whatsapp_business_account", "entry" => [%{"id" => "1234567890"}]}

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == message.bsp_status
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
        &Map.merge(%{"recipient_id" => "919999999999", "timestamp" => "1791897501"}, &1)
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
