defmodule GlificWeb.Providers.Maytapi.Controllers.MessageControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Groups.WhatsappGroup,
    Messages.Message,
    Partners,
    Repo,
    Seeds.SeedsDev,
    WAManagedPhones
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
    "phone_id" => 42_908,
    "message" => %{
      "type" => "text",
      "text" => "test message",
      "id" => "false_120363027326493365@g.us_3EB037B863B86D2AF69DD8_919642961343@c.us",
      "_serialized" => "false_120363027326493365@g.us_3EB037B863B86D2AF69DD8_919642961343@c.us",
      "fromMe" => false
    },
    "user" => %{
      "id" => "919917443994@c.us",
      "name" => "user_a",
      "phone" => "919917443994"
    },
    "conversation" => "120363213149844251@g.us",
    "conversation_name" => "Default Group name",
    "receiver" => "919917443955",
    "timestamp" => 1_707_216_634,
    "type" => "message",
    "reply" =>
      "https =>//api.maytapi.com/api/5351f38b-c0ae-49c4-9e43-427cb901b0f5/42906/sendMessage",
    "productId" => "5351f38b-c0ae-49c4-9e43-427cb901b0f7",
    "phoneId" => 42_908
  }

  @text_message_webhook_new_group %{
    "product_id" => "5351f38b-c0ae-49c4-9e43-427cb901b0f7",
    "phone_id" => 42_908,
    "message" => %{
      "type" => "text",
      "text" => "test message",
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
    "conversation_name" => "Group B",
    "receiver" => "919917443955",
    "timestamp" => 1_707_216_634,
    "type" => "message",
    "reply" =>
      "https =>//api.maytapi.com/api/5351f38b-c0ae-49c4-9e43-427cb901b0f5/42906/sendMessage",
    "productId" => "5351f38b-c0ae-49c4-9e43-427cb901b0f7",
    "phoneId" => 42_908
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)

    Partners.create_credential(%{
      organization_id: organization.id,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{
        "phone" => "917834811114",
        "phone_id" => "42093",
        "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
        "token" => "f4f38e00-3a50-4892-99ce-a282fe24d041"
      },
      is_active: true
    })

    Tesla.Mock.mock(fn
      %{
        method: :get,
        url: "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/42093/getGroups"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "{\"count\":79,\"data\":[{\"admins\":[\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363213149844251@g.us\",\"name\":\"Default Group name\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\",\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363203450035277@g.us\",\"name\":\"Movie Plan\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363218884368888@g.us\",\"name\":\"Developer Group\",\"participants\":[\"917834811114@c.us\"]}],\"limit\":500,\"success\":true,\"total\":79}"
        }

      %{
        method: :get,
        url: "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/listPhones"
      } ->
        %Tesla.Env{
          status: 200,
          body:
            "[{\"id\":42093,\"number\":\"917834811114\",\"status\":\"active\",\"type\":\"whatsapp\",\"name\":\"\",\"data\":{},\"multi_device\":true}]"
        }
    end)

    assert :ok == WAManagedPhones.fetch_wa_managed_phones(organization.id)

    assert :ok ==
             WhatsappGroup.list_wa_groups(organization.id)

    SeedsDev.seed_tag()
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    {:ok, %{organization_id: organization.id}}
  end

  describe "handler" do
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

    test "Incoming text message without phone should raise exception", %{conn: conn} do
      text_msg_webhook = Map.delete(@text_message_webhook, "user")
      assert_raise RuntimeError, fn -> post(conn, "/maytapi", text_msg_webhook) end

      text_msg_webhook = put_in(@text_message_webhook, ["user", "phone"], nil)
      assert_raise RuntimeError, fn -> post(conn, "/maytapi", text_msg_webhook) end

      text_msg_webhook = put_in(@text_message_webhook, ["user", "phone"], "")
      assert_raise RuntimeError, fn -> post(conn, "/maytapi", text_msg_webhook) end
    end

    test "Incoming text message should be stored in the database, new contact", %{conn: conn} do
      conn = post(conn, "/maytapi", @text_message_webhook)
      assert conn.halted

      bsp_message_id = get_in(@text_message_webhook, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:receiver, :sender, :media, :contact, :group])

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

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
      assert message.message_type == "WA"
      assert message.group.bsp_id == "120363213149844251@g.us"
    end

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

      conn = assign(conn_bak, :organization_id, 1)
      conn = post(conn, "/maytapi", text_webhook_params)

      assert conn.halted

      bsp_message_id = get_in(text_webhook_params, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:receiver, :sender, :media, :contact, :group])

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
      assert message.group.bsp_id == "120363213149844251@g.us"
    end

    test "Incoming text message should be stored in the database, but group doesnt exist, so creates group",
         %{
           conn: conn
         } do
      conn = post(conn, "/maytapi", @text_message_webhook_new_group)
      assert conn.halted

      bsp_message_id = get_in(@text_message_webhook_new_group, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:receiver, :sender, :media, :contact, :group])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      # ensure the message has been received by the mock
      assert_receive :received_message_to_process

      assert message.sender.last_message_at != nil
      assert true == Glific.in_past_time(message.sender.last_message_at, :seconds, 10)

      # Sender should be stored into the db
      assert message.sender.phone ==
               get_in(@text_message_webhook_new_group, ["user", "phone"])

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
      assert message.message_type == "WA"
      assert !is_nil(message.group_id)
      assert message.group.bsp_id == "120363027326493365@g.us"
    end
  end
end
