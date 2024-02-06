defmodule GlificWeb.Providers.Maytapi.Controllers.MessageControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Messages.Message,
    Repo,
    Seeds.SeedsDev
  }

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
      "id" => "919642961323@c.us",
      "name" => "user_a",
      "phone" => "919642961323"
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
    @tag :maytapi_msg_controller
    test "Incoming text message without phone should raise exception", %{conn: conn} do
      text_msg_webhook = Map.delete(@text_message_webhook, "user")
      assert_raise RuntimeError, fn -> post(conn, "/maytapi", text_msg_webhook) end

      text_msg_webhook = put_in(@text_message_webhook, ["user", "phone"], nil)
      assert_raise RuntimeError, fn -> post(conn, "/maytapi", text_msg_webhook) end

      text_msg_webhook = put_in(@text_message_webhook, ["user", "phone"], "")
      assert_raise RuntimeError, fn -> post(conn, "/maytapi", text_msg_webhook) end
    end

    @tag :maytapi_msg_controller_2
    test "Incoming text message should be stored in the database", %{conn: conn} do
      conn = post(conn, "/maytapi", @text_message_webhook)
      assert conn.halted

      bsp_message_id = get_in(@text_message_webhook, ["message", "id"]) |> IO.inspect()

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

    # TODO: Tests for checking the message_type and contact_type
  end
end
