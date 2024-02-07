defmodule GlificWeb.Providers.Maytapi.Controllers.MessageControllerTest do
  use GlificWeb.ConnCase

  # TODO: Tests for checking the message_type and contact_type
  # TODO: Test for updating contacts
  #

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Messages.Message,
    Repo,
    Seeds.SeedsDev
  }

  import Ecto.Query

  @message_request_params %{
    "app" => "Glific Mock App",
    "timestamp" => 1_580_227_766_370,
    "version" => 2,
    "type" => "message",
    "payload" => %{
      "id" => "ABEGkYaYVSEEAhAL3SLAWwHKeKrt6s3FKB0c",
      "source" => "919917443994",
      "payload" => %{
        "text" => "Hi"
      },
      "sender" => %{
        "phone" => "919917443994",
        "name" => "Smit",
        "country_code" => "91",
        "dial_code" => "8x98xx21x4"
      }
    }
  }

  @text_message_webhook %{
    "product_id" => "5351f38b-c0ae-49c4-9e43-427cb901b0f7",
    "phone_id" => 42908,
    "message" => %{
      "type" => "text",
      "text" => "It's like a mini-sprint- Almost half of the team is there",
      "id" => "false_120363027326493365@g.us_3EB037B863B86D2AF69DD8_919642961343@c.us",
      "_serialized" => "false_120363027326493365@g.us_3EB037B863B86D2AF69DD8_919642961343@c.us",
      "fromMe" => false
    },
    "user" => %{
      "id" => "919917443994@c.us",
      "name" => "user_a",
      "phone" => "919917443994"
    },
    "conversation" => "120363027326493365@g.us",
    "conversation_name" => "Tech4Dev Team",
    "receiver" => "919917443955",
    "timestamp" => 1_707_216_634,
    "type" => "message",
    "reply" =>
      "https =>//api.maytapi.com/api/5351f38b-c0ae-49c4-9e43-427cb901b0f5/42906/sendMessage",
    "productId" => "5351f38b-c0ae-49c4-9e43-427cb901b0f7",
    "phoneId" => 42908
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_tag()
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    {:ok, %{organization_id: organization.id}}
  end

  describe "handler" do
    @tag :maytapi_msg_controller
    test "handler should return nil data", %{conn: conn} do
      conn = post(conn, "/maytapi", @message_request_params)
      assert json_response(conn, 200) == nil
    end
  end

  describe "text" do
    setup do
      message_payload = %{
        "text" => "Inbound Message"
      }

      message_params =
        @message_request_params
        |> put_in(["payload", "type"], "text")
        |> put_in(["payload", "id"], Faker.String.base64(36))
        |> put_in(["payload", "payload"], message_payload)

      %{message_params: message_params}
    end

    @tag :maytapi_msg_controller
    test "Incoming text message without phone should raise exception", %{conn: conn} do
      text_msg_webhook = Map.delete(@text_message_webhook, "user")
      assert_raise RuntimeError, fn -> post(conn, "/maytapi", text_msg_webhook) end

      text_msg_webhook = put_in(@text_message_webhook, ["user", "phone"], nil)
      assert_raise RuntimeError, fn -> post(conn, "/maytapi", text_msg_webhook) end

      text_msg_webhook = put_in(@text_message_webhook, ["user", "phone"], "")
      assert_raise RuntimeError, fn -> post(conn, "/maytapi", text_msg_webhook) end
    end

    @tag :maytapi_msg_controller
    test "Incoming text message should be stored in the database", %{conn: conn} do
      conn = post(conn, "/maytapi", @text_message_webhook)
      assert conn.halted

      bsp_message_id = get_in(@text_message_webhook, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:receiver, :sender, :media])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      # ensure the message has been received by the mock
      assert_receive :received_message_to_process

      assert message.sender.last_message_at != nil
      assert true == Glific.in_past_time(message.sender.last_message_at, :seconds, 10)

      # Sender should be stored into the db
      assert message.sender.phone ==
               get_in(@text_message_webhook, ["user", "phone"])
    end

    @tag :maytapi_msg_controller
    test "Incoming text for blocked contact will not be store in the database",
         %{conn: conn} do
      bsp_message_id = get_in(@text_message_webhook, ["user", "id"])

      [contact | _tail] = Contacts.list_contacts(%{})

      {:ok, _contact} = Contacts.update_contact(contact, %{status: :blocked})

      message_params = @text_message_webhook

      conn = post(conn, "/maytapi", message_params)
      assert conn.halted

      {:error, ["Elixir.Glific.Messages.Message", "Resource not found"]} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })
    end

    @tag :maytapi_msg_controller_2
    test "Updating the contact_type to WABA+WA due to sender contact already existing", %{
      conn: conn,
      message_params: message_params
    } do
      conn_bak = conn
      # handling a message from gupshup, so that the phone number will be already existing
      # in contacts table.
      conn = post(conn, "/gupshup", message_params)
      assert conn.halted
      bsp_message_id = get_in(message_params, ["payload", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:receiver, :sender, :media])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      # ensure the message has been received by the mock
      assert_receive :received_message_to_process

      assert message.sender.last_message_at != nil
      assert true == Glific.in_past_time(message.sender.last_message_at, :seconds, 10)

      # Sender should be stored into the db
      assert message.sender.phone ==
               get_in(message_params, ["payload", "sender", "phone"])

      # handling text message from maytapi

      text_webhook_params =
        @text_message_webhook
        |> put_in(["user", "phone"], get_in(message_params, ["payload", "sender", "phone"]))

      Contact
      |> where([contact], contact.phone == ^text_webhook_params["user"]["phone"])
      |> Repo.one()

      conn = assign(conn_bak, :organization_id, 1)
      conn = post(conn, "/maytapi", text_webhook_params)

      assert conn.halted

      bsp_message_id = get_in(text_webhook_params, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:receiver, :sender, :media, :contact])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      # ensure the message has been received by the mock
      assert_receive :received_message_to_process

      assert message.sender.last_message_at != nil
      assert true == Glific.in_past_time(message.sender.last_message_at, :seconds, 10)

      # Sender should be stored into the db
      assert message.sender.phone ==
               get_in(text_webhook_params, ["user", "phone"])

      assert message.contact.contact_type == "WABA+WA"
    end
  end
end
