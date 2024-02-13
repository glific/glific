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
    "product_id" => "ce2a5bf0-7a8d-4cc3-8202-a645dd5deccb",
    "phone_id" => 1_150,
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
    "conversation" => "120363213149844251@g.us",
    "conversation_name" => "Tech4Dev Team",
    "receiver" => "919917443955",
    "timestamp" => 1_707_216_634,
    "type" => "message",
    "reply" =>
      "https =>//api.maytapi.com/api/5351f38b-c0ae-49c4-9e43-427cb901b0f5/1150/sendMessage",
    "productId" => "ce2a5bf0-7a8d-4cc3-8202-a645dd5deccb",
    "phoneId" => 1_150
  }

  @media_message_webhook %{
    "product_id" => "ce2a5bf0-7a8d-4cc3-8202-a645dd5deccb",
    "phone_id" => 1150,
    "message" => %{
      "type" => "image",
      "url" => "https://cdnydm.com/wh/x7Yr1HQYy_m9RZ_xcJ6dw.jpeg?size=1280x960",
      "mime" => "image/jpeg",
      "filename" =>
        "false_120363027326493365@g.us_0C623FCC2528444570C488FB229F7628_919917443994@c.us.jpeg",
      "caption" => "",
      "id" => "false_120363027326493365@g.us_0C623FCC2528444570C488FB229F7628_919917443994@c.us",
      "_serialized" =>
        "false_120363027326493365@g.us_0C623FCC2528444570C488FB229F7628_919917443994@c.us",
      "fromMe" => false
    },
    "user" => %{
      "id" => "919917443994@c.us",
      "name" => "name_a",
      "phone" => "919917443994"
    },
    "conversation" => "120363027326493365@g.us",
    "conversation_name" => "Tech4Dev Team",
    "receiver" => "919917443955",
    "timestamp" => 1_707_216_553,
    "type" => "message",
    "reply" =>
      "https://api.maytapi.com/api/ce2a5bf0-7a8d-4cc3-8202-a645dd5deccb/1150/sendMessage",
    "productId" => "ce2a5bf0-7a8d-4cc3-8202-a645dd5deccb",
    "phoneId" => 1150
  }

  @text_message_webhook_invalid_group %{
    "product_id" => "ce2a5bf0-7a8d-4cc3-8202-a645dd5deccb",
    "phone_id" => 1_150,
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
    "conversation_name" => "Tech4Dev Team invalid",
    "receiver" => "919917443955",
    "timestamp" => 1_707_216_634,
    "type" => "message",
    "reply" =>
      "https =>//api.maytapi.com/api/5351f38b-c0ae-49c4-9e43-427cb901b0f5/1150/sendMessage",
    "productId" => "ce2a5bf0-7a8d-4cc3-8202-a645dd5deccb",
    "phoneId" => 1_150
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
            "{\"count\":79,\"data\":[{\"admins\":[\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363213149844251@g.us\",\"name\":\"Tech4Dev Team\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\",\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363203450035277@g.us\",\"name\":\"Movie Plan\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363218884368888@g.us\",\"name\":\"Developer Group\",\"participants\":[\"917834811114@c.us\"]}],\"limit\":500,\"success\":true,\"total\":79}"
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

    test "Incoming text message should be stored in the database, but group doesnt exist", %{
      conn: conn
    } do
      conn = post(conn, "/maytapi", @text_message_webhook_invalid_group)
      assert conn.halted

      bsp_message_id = get_in(@text_message_webhook_invalid_group, ["message", "id"])

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
               get_in(@text_message_webhook_invalid_group, ["user", "phone"])

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
      assert message.message_type == "WA"
      assert message.group_id == nil
    end
  end

  describe "media" do
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

    test "Incoming media message without phone should raise exception", %{conn: conn} do
      media_msg_webhook = Map.delete(@media_message_webhook, "user")
      assert_raise RuntimeError, fn -> post(conn, "/maytapi", media_msg_webhook) end

      media_msg_webhook = put_in(@media_message_webhook, ["user", "phone"], nil)
      assert_raise RuntimeError, fn -> post(conn, "/maytapi", media_msg_webhook) end

      media_msg_webhook = put_in(@media_message_webhook, ["user", "phone"], "")
      assert_raise RuntimeError, fn -> post(conn, "/maytapi", media_msg_webhook) end
    end

    test "Incoming text message should be stored in the database, new contact", %{conn: conn} do
      conn = post(conn, "/maytapi", @media_message_webhook)
      assert conn.halted

      bsp_message_id = get_in(@media_message_webhook, ["message", "id"])

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
               get_in(@media_message_webhook, ["user", "phone"])

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
      assert message.message_type == "WA"
      assert message.group.label == "Tech4Dev Team"
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
        @media_message_webhook
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
      assert message.group.label == "Tech4Dev Team"
    end

    test "Incoming text message should be stored in the database, but group doesnt exist", %{
      conn: conn
    } do
      invalid_resp = @media_message_webhook |> Map.put("conversation_name", "Tech4d invalid")
      conn = post(conn, "/maytapi", invalid_resp)
      assert conn.halted

      bsp_message_id = get_in(invalid_resp, ["message", "id"])

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
               get_in(invalid_resp, ["user", "phone"])

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
      assert message.message_type == "WA"
      assert message.group_id == nil
    end
  end
end
