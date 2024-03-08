defmodule GlificWeb.Providers.Maytapi.Controllers.MessageControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Groups.WAGroup,
    Groups.WAGroups,
    Messages.Message,
    Partners,
    Repo,
    Seeds.SeedsDev,
    WAGroup.WAMessage,
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
    "receiver" => "917834811114",
    "timestamp" => 1_707_216_634,
    "type" => "message",
    "reply" =>
      "https =>//api.maytapi.com/api/5351f38b-c0ae-49c4-9e43-427cb901b0f5/1150/sendMessage",
    "productId" => "ce2a5bf0-7a8d-4cc3-8202-a645dd5deccb",
    "phoneId" => 1_150
  }

  @text_message_from_wa_managed_phone_webhook %{
    "product_id" => "ce2a5bf0-7a8d-4cc3-8202-a645dd5deccb",
    "phone_id" => 1_150,
    "message" => %{
      "type" => "text",
      "text" => "from wa_managed phone test message",
      "id" => "false_120363027326493365@g.us_3EB037B863B86D2AF69DD8_919642961232@c.us",
      "_serialized" => "false_120363027326493365@g.us_3EB037B863B86D2AF69DD8_919642961232@c.us",
      "fromMe" => true
    },
    "user" => %{
      "id" => "919917443994@c.us",
      "name" => "user_a",
      "phone" => "919917443994"
    },
    "conversation" => "120363213149844251@g.us",
    "conversation_name" => "Default Group name",
    "receiver" => "917834811114",
    "timestamp" => 1_707_216_634,
    "type" => "message",
    "reply" =>
      "https =>//api.maytapi.com/api/5351f38b-c0ae-49c4-9e43-427cb901b0f5/1150/sendMessage",
    "productId" => "ce2a5bf0-7a8d-4cc3-8202-a645dd5deccb",
    "phoneId" => 1_150
  }

  @text_dm_message_webhook %{
    "product_id" => "ce2a5bf0-7a8d-4cc3-8202-a645dd5deccb",
    "phone_id" => 1_150,
    "message" => %{
      "type" => "text",
      "text" => "test message",
      "id" => "false_120363027326493365@g.us_3EB037B863B86D2AF69DD8_919642961483@c.us",
      "_serialized" => "false_120363027326493365@g.us_3EB037B863B86D2AF69DD8_919642961483@c.us",
      "fromMe" => false
    },
    "user" => %{
      "id" => "919917443994@c.us",
      "name" => "user_a",
      "phone" => "919917443994"
    },
    "conversation" => "",
    "conversation_name" => "",
    "receiver" => "917834811114",
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
    "conversation" => "120363213149844251@g.us",
    "conversation_name" => "Group C",
    "receiver" => "917834811114",
    "timestamp" => 1_707_216_553,
    "type" => "message",
    "reply" =>
      "https://api.maytapi.com/api/ce2a5bf0-7a8d-4cc3-8202-a645dd5deccb/1150/sendMessage",
    "productId" => "ce2a5bf0-7a8d-4cc3-8202-a645dd5deccb",
    "phoneId" => 1150
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
    "receiver" => "917834811114",
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
             WAGroups.fetch_wa_groups(organization.id)

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
      message_params =
        @text_message_webhook
        |> put_in(["message", "id"], Ecto.UUID.generate())

      conn = post(conn, "/maytapi", message_params)
      assert conn.halted

      bsp_message_id = get_in(message_params, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(WAMessage, %{
          bsp_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :contact])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
    end

    test "Incoming direct text message should be stored in the database with is_dm true", %{
      conn: conn
    } do
      message_params =
        @text_dm_message_webhook
        |> put_in(["message", "id"], Ecto.UUID.generate())

      conn = post(conn, "/maytapi", message_params)
      assert conn.halted

      bsp_message_id = get_in(message_params, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(WAMessage, %{
          bsp_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:contact])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound
      assert message.is_dm == true

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
    end

    test "Incoming direct text message should be stored in the database with fromMe as true", %{
      conn: conn
    } do
      message_params =
        @text_message_from_wa_managed_phone_webhook
        |> put_in(["message", "id"], Ecto.UUID.generate())

      conn = post(conn, "/maytapi", message_params)
      assert conn.halted

      bsp_message_id = get_in(message_params, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(WAMessage, %{
          bsp_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:contact])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :outbound
      assert message.is_dm == false

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
    end

    test "Updating the contact_type to WABA+WA due to sender contact already existing", %{
      conn: conn,
      message_params: message_params
    } do
      # handling a message from gupshup, so that the phone number will be already existing
      # in contacts table.
      gupshup_conn = post(conn, "/gupshup", message_params)
      assert gupshup_conn.halted
      bsp_message_id = get_in(message_params, ["payload", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: gupshup_conn.assigns[:organization_id]
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
        |> put_in(["message", "id"], Ecto.UUID.generate())
        |> put_in(["user", "phone"], get_in(message_params, ["payload", "sender", "phone"]))

      gupshup_conn = post(conn, "/maytapi", text_webhook_params)

      assert gupshup_conn.halted

      bsp_message_id = get_in(text_webhook_params, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(WAMessage, %{
          bsp_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :contact])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      assert message.contact.contact_type == "WABA+WA"
    end

    test "Incoming text message should be stored in the database, but group doesnt exist, so creates group",
         %{
           conn: conn
         } do
      text_message_webhook_new_group =
        @text_message_webhook_new_group
        |> put_in(["message", "id"], Ecto.UUID.generate())

      conn = post(conn, "/maytapi", text_message_webhook_new_group)
      assert conn.halted

      bsp_message_id = get_in(text_message_webhook_new_group, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(WAMessage, %{
          bsp_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :contact])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
      group_bsp_id = get_in(text_message_webhook_new_group, ["conversation"])
      payload_group_name = get_in(text_message_webhook_new_group, ["conversation_name"])

      {:ok, wa_group} =
        Repo.fetch_by(WAGroup, %{
          bsp_id: group_bsp_id,
          organization_id: conn.assigns[:organization_id]
        })

      assert wa_group.label == payload_group_name
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

    test "Incoming media message should be stored in the database, new contact", %{conn: conn} do
      media_message_webhook =
        @media_message_webhook
        |> put_in(["message", "id"], Ecto.UUID.generate())

      conn = post(conn, "/maytapi", media_message_webhook)
      assert conn.halted

      bsp_message_id = get_in(media_message_webhook, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(WAMessage, %{
          bsp_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :contact])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
    end

    test "Incoming media message should be stored in the database where media is a file", %{
      conn: conn
    } do
      media_message_payload =
        put_in(@media_message_webhook, ["message", "type"], "document")
        |> put_in(["message", "mime"], "application/pdf")
        |> put_in(["message", "filename"], "file.pdf")
        |> put_in(["message", "url"], "https://cdnydm.com/wh/x7Yr1HQYy_m9RZ_xcJ6dw.pdf")
        |> put_in(["message", "id"], Ecto.UUID.generate())

      conn = post(conn, "/maytapi", media_message_payload)
      assert conn.halted

      bsp_message_id = get_in(media_message_payload, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(WAMessage, %{
          bsp_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :contact])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
      assert message.media.content_type == "document"
    end

    test "Incoming media message should be stored in the database where media is a sticker", %{
      conn: conn
    } do
      media_message_payload =
        put_in(@media_message_webhook, ["message", "type"], "sticker")
        |> put_in(["message", "id"], Ecto.UUID.generate())
        |> put_in(["message", "mime"], "image/webp")
        |> put_in(["message", "filename"], "sticker.webp")
        |> put_in(["message", "url"], "https://cdnydm.com/wh/x7Yr1HQYy_m9RZ_xcJ6dw.webp")

      conn = post(conn, "/maytapi", media_message_payload)
      assert conn.halted

      bsp_message_id = get_in(media_message_payload, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(WAMessage, %{
          bsp_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :contact])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
      assert message.media.content_type == "sticker"
    end

    test "Incoming media message should be stored in the database where media is a whatsapp audio",
         %{conn: conn} do
      media_message_payload =
        put_in(@media_message_webhook, ["message", "type"], "ptt")
        |> put_in(["message", "id"], Ecto.UUID.generate())
        |> put_in(["message", "mime"], "audio/ogg")
        |> put_in(["message", "filename"], "audio.oga")
        |> put_in(["message", "url"], "https://cdnydm.com/wh/x7Yr1HQYy_m9RZ_xcJ6dw.oga")

      conn = post(conn, "/maytapi", media_message_payload)
      assert conn.halted

      bsp_message_id = get_in(media_message_payload, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(WAMessage, %{
          bsp_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :contact])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
      assert message.media.content_type == "ptt"
    end

    test "Incoming media message should be stored in the database where media is a uploaded audio",
         %{conn: conn} do
      media_message_payload =
        put_in(@media_message_webhook, ["message", "type"], "audio")
        |> put_in(["message", "id"], Ecto.UUID.generate())
        |> put_in(["message", "mime"], "audio/acc")
        |> put_in(["message", "filename"], "audio.us")
        |> put_in(["message", "url"], "https://cdnydm.com/wh/x7Yr1HQYy_m9RZ_xcJ6dw.us")

      conn = post(conn, "/maytapi", media_message_payload)
      assert conn.halted

      bsp_message_id = get_in(media_message_payload, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(WAMessage, %{
          bsp_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :contact])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"
      assert message.media.content_type == "audio"
    end

    test "Updating the contact_type to WABA+WA due to sender contact already existing", %{
      conn: conn,
      message_params: message_params
    } do
      # handling a message from gupshup, so that the phone number will be already existing
      # in contacts table.
      gupshup_conn = post(conn, "/gupshup", message_params)
      assert gupshup_conn.halted
      bsp_message_id = get_in(message_params, ["payload", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: gupshup_conn.assigns[:organization_id]
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

      gupshup_conn = post(conn, "/maytapi", text_webhook_params)

      assert gupshup_conn.halted

      bsp_message_id = get_in(text_webhook_params, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(WAMessage, %{
          bsp_id: bsp_message_id,
          organization_id: gupshup_conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :contact])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      assert message.contact.contact_type == "WABA+WA"
    end

    test "Incoming media message should be stored in the database, but group doesnt exist, so creates group",
         %{
           conn: conn
         } do
      media_message_new_group =
        @media_message_webhook
        |> Map.put("conversation", "120363027326493365@g.us")
        |> put_in(["message", "id"], Ecto.UUID.generate())

      conn = post(conn, "/maytapi", media_message_new_group)
      assert conn.halted

      bsp_message_id = get_in(media_message_new_group, ["message", "id"])

      {:ok, message} =
        Repo.fetch_by(WAMessage, %{
          bsp_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :contact])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      # contact_type and message_type should be updated for wa groups
      assert message.contact.contact_type == "WA"

      group_bsp_id = get_in(media_message_new_group, ["conversation"])
      payload_group_name = get_in(media_message_new_group, ["conversation_name"])

      {:ok, wa_group} =
        Repo.fetch_by(WAGroup, %{
          bsp_id: group_bsp_id,
          organization_id: conn.assigns[:organization_id]
        })

      assert wa_group.label == payload_group_name
    end
  end
end
