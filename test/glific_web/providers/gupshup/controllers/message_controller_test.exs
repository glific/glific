defmodule GlificWeb.Providers.Gupshup.Controllers.MessageControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Contacts.Location,
    Messages.Message,
    Repo,
    Seeds.SeedsDev
  }

  @message_request_params %{
    "app" => "GlifMock App",
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

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_tag()
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    {:ok, %{organization_id: organization.id}}
  end

  describe "handler" do
    test "handler should return nil data", %{conn: conn} do
      conn = post(conn, "/gupshup", @message_request_params)
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

    test "Incoming text message should be stored in the database",
         %{conn: conn, message_params: message_params} do
      conn = post(conn, "/gupshup", message_params)
      json_response(conn, 200)
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
    end
  end

  describe "media" do
    setup do
      image_payload = %{
        "caption" => Faker.Lorem.sentence(),
        "url" => Faker.Avatar.image_url(200, 200),
        "urlExpiry" => 1_580_832_695_997
      }

      message_params =
        @message_request_params
        |> put_in(["payload", "type"], "image")
        |> put_in(["payload", "id"], Faker.String.base64(36))
        |> put_in(["payload", "payload"], image_payload)

      %{message_params: message_params, image_payload: image_payload}
    end

    test "Incoming image message should be stored in the database",
         setup_config = %{conn: conn} do
      conn = post(conn, "/gupshup", setup_config.message_params)
      json_response(conn, 200)

      bsp_message_id = get_in(setup_config.message_params, ["payload", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:sender, :media])

      # Provider message id should be updated
      assert message.bsp_status == :delivered
      assert message.flow == :inbound

      # ensure the message has been received by the mock
      assert_receive :received_message_to_process

      # test media fields
      assert message.media.caption == setup_config.image_payload["caption"]
      assert message.media.url == setup_config.image_payload["url"]
      assert message.media.source_url == setup_config.image_payload["url"]

      assert true == Glific.in_past_time(message.sender.last_message_at, :seconds, 10)

      # Sender should be stored into the db
      assert message.sender.phone ==
               get_in(setup_config.message_params, ["payload", "sender", "phone"])
    end

    test "Incoming audio message should be stored in the database",
         setup_config = %{conn: conn} do
      message_params =
        setup_config.message_params
        |> put_in(["payload", "type"], "audio")
        |> put_in(["payload", "payload", "caption"], nil)

      conn = post(conn, "/gupshup", message_params)
      json_response(conn, 200)
      bsp_message_id = get_in(message_params, ["payload", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :sender])

      # ensure the message has been received by the mock
      assert_receive :received_message_to_process

      # test media fields
      assert message.media.url == setup_config.image_payload["url"]
      assert message.media.source_url == setup_config.image_payload["url"]

      # Sender should be stored into the db
      assert message.sender.phone ==
               get_in(setup_config.message_params, ["payload", "sender", "phone"])
    end

    test "Incoming video message should be stored in the database",
         setup_config = %{conn: conn} do
      message_params =
        setup_config.message_params
        |> put_in(["payload", "type"], "video")

      conn = post(conn, "/gupshup", message_params)
      json_response(conn, 200)
      bsp_message_id = get_in(message_params, ["payload", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :sender])

      # ensure the message has been received by the mock
      assert_receive :received_message_to_process

      # test media fields
      assert message.media.url == setup_config.image_payload["url"]
      assert message.media.source_url == setup_config.image_payload["url"]

      # Sender should be stored into the db
      assert message.sender.phone ==
               get_in(setup_config.message_params, ["payload", "sender", "phone"])
    end

    test "Incoming file message should be stored in the database", setup_config = %{conn: conn} do
      message_params =
        setup_config.message_params
        |> put_in(["payload", "type"], "file")

      conn = post(conn, "/gupshup", message_params)
      json_response(conn, 200)
      bsp_message_id = get_in(message_params, ["payload", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :sender])

      # ensure the message has been received by the mock
      assert_receive :received_message_to_process

      # test media fields
      assert message.media.url == setup_config.image_payload["url"]
      assert message.media.source_url == setup_config.image_payload["url"]

      # Sender should be stored into the db
      assert message.sender.phone ==
               get_in(setup_config.message_params, ["payload", "sender", "phone"])
    end

    test "Incoming sticker message should be stored in the database",
         setup_config = %{conn: conn} do
      message_params =
        setup_config.message_params
        |> put_in(["payload", "type"], "sticker")

      conn = post(conn, "/gupshup", message_params)
      json_response(conn, 200)
      bsp_message_id = get_in(message_params, ["payload", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :sender])

      # ensure the message has been received by the mock
      assert_receive :received_message_to_process

      # test media fields
      assert message.media.url == setup_config.image_payload["url"]
      assert message.media.source_url == setup_config.image_payload["url"]

      # Sender should be stored into the db
      assert message.sender.phone ==
               get_in(setup_config.message_params, ["payload", "sender", "phone"])
    end
  end

  describe "location" do
    setup do
      location_payload = %{
        "longitude" => Faker.Address.longitude(),
        "latitude" => Faker.Address.latitude()
      }

      message_params =
        @message_request_params
        |> put_in(["payload", "type"], "location")
        |> put_in(["payload", "id"], Faker.String.base64(36))
        |> put_in(["payload", "payload"], location_payload)

      %{message_params: message_params, location_payload: location_payload}
    end

    test "Incoming location message and contact's location should be stored in the database",
         setup_config = %{conn: conn} do
      message_params = setup_config.message_params

      conn = post(conn, "/gupshup", message_params)
      json_response(conn, 200)
      bsp_message_id = get_in(message_params, ["payload", "id"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :sender])

      {:ok, location} = Repo.fetch_by(Location, %{message_id: message.id})

      # ensure the message has been received by the mock
      assert_receive :received_message_to_process

      # test location fields
      assert location.longitude == setup_config.location_payload["longitude"]
    end
  end
end
