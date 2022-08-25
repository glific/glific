defmodule GlificWeb.Providers.Gupshup.Controllers.BillingEventControllerTest do
  use GlificWeb.ConnCase
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Messages,
    Messages.MessageConversation,
    Repo,
    Seeds.SeedsDev
  }

  @billing_event_request_params %{
    "app" => "Glific App",
    "payload" => %{
      "deductions" => %{
        "billable" => true,
        "model" => "CBP",
        "source" => "whatsapp",
        "type" => "UIC"
      },
      "references" => %{
        "conversationId" => "c3dcdb2f4f227931248cc080c387e484",
        "destination" => "1234567851",
        "gsId" => "3b3e7121-3c8c-4347-8d18-7aa0bc3be374",
        "id" => "gBEGkZdhAzaXAgmpAw6G7Oc_XIg"
      }
    },
    "timestamp" => 1_661_319_436_533,
    "type" => "billing-event",
    "version" => 2
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  describe "status" do
    test "handler should return nil data", %{conn: conn} do
      [message | _] = Messages.list_messages(%{})
      contact = Contacts.get_contact!(message.contact_id)

      billing_event_params =
        @billing_event_request_params
        |> put_in(["payload", "references", "destination"], contact.phone)
        |> put_in(["payload", "references", "gsId"], message.bsp_message_id)

      conn = post(conn, "/gupshup", billing_event_params)
      assert json_response(conn, 200) == nil

      {:ok, message_conversation} =
        Repo.fetch_by(MessageConversation, %{
          conversation_id: "c3dcdb2f4f227931248cc080c387e484"
        })

      assert message_conversation.is_billable == true
      assert message_conversation.deduction_type == "UIC"
      assert message_conversation.message_id == message.id
    end
  end
end
