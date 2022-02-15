defmodule GlificWeb.Providers.Gupshup.Enterprise.Controllers.MessageControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Contacts,
    Contacts.Location,
    Messages.Message,
    Repo,
    Seeds.SeedsDev
  }

  @message_request_params %{
    "mobile" => "919917443994",
    "name" => "Smit",
    "text" => "Hello to enterprise",
    "timestamp" => "1644911629000",
    "type" => "text",
    "replyId" => Faker.String.base64(36),
    "waNumber" => "911244006972"
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    {:ok, %{organization_id: organization.id}}
  end

  describe "text" do
    setup do
      message_params =
        @message_request_params
        |> put_in(["type"], "text")
        |> put_in(["text"], "Inbound Message")

      %{message_params: message_params}
    end

    test "Incoming text message without phone should raise exception",
         %{conn: conn, message_params: message_params} do
      message_params = put_in(message_params, ["mobile"], "")
      assert_raise RuntimeError, fn -> post(conn, "/gupshup-enterprise", message_params) end

      message_params = put_in(message_params, ["mobile"], nil)
      assert_raise RuntimeError, fn -> post(conn, "/gupshup-enterprise", message_params) end
    end

    test "Incoming text message should be stored in the database",
         %{conn: conn, message_params: message_params} do
      conn = post(conn, "/gupshup-enterprise", message_params)
      assert conn.halted
      bsp_message_id = get_in(message_params, ["replyId"])

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
               get_in(message_params, ["mobile"])
    end

    test "Incoming text for blocked contact will not be store in the database",
         %{conn: conn, message_params: message_params} do
      bsp_message_id = Ecto.UUID.generate()

      [contact | _tail] = Contacts.list_contacts(%{})

      {:ok, contact} = Contacts.update_contact(contact, %{status: :blocked})

      message_params =
        message_params
        |> put_in(["replyId"], bsp_message_id)
        |> put_in(["mobile"], contact.phone)

      conn = post(conn, "/gupshup-enterprise", message_params)
      assert conn.halted

      {:error, ["Elixir.Glific.Messages.Message", "Resource not found"]} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })
    end
  end

  describe "media" do
    setup do
      media_payload = %{
        "signature" => Faker.String.base64(36),
        "url" => Faker.Avatar.image_url(200, 200)
      }

      %{message_params: @message_request_params, media_payload: media_payload}
    end

    test "Incoming image message should be stored in the database",
         setup_config = %{conn: conn} do
      image_payload =
        setup_config.media_payload
        |> Map.put("mime_type", "image/jpeg")
        |> Map.put("caption", Faker.Lorem.sentence())

      message_params =
        setup_config.message_params
        |> put_in(["type"], "image")
        |> Map.put("image", Jason.encode!(image_payload))

      conn = post(conn, "/gupshup-enterprise", message_params)
      assert conn.halted

      bsp_message_id = get_in(message_params, ["replyId"])

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
      assert message.media.caption == image_payload["caption"]
      assert message.media.url == image_payload["url"] <> image_payload["signature"]
      assert message.media.source_url == image_payload["url"] <> image_payload["signature"]

      assert true == Glific.in_past_time(message.sender.last_message_at, :seconds, 10)

      # Sender should be stored into the db
      assert message.sender.phone ==
               get_in(message_params, ["mobile"])
    end

    test "Incoming audio message should be stored in the database",
         setup_config = %{conn: conn} do
      audio_payload =
        setup_config.media_payload
        |> Map.put("mime_type", "audio/mpeg")

      message_params =
        setup_config.message_params
        |> put_in(["type"], "audio")
        |> Map.put("audio", Jason.encode!(audio_payload))

      conn = post(conn, "/gupshup-enterprise", message_params)
      assert conn.halted
      bsp_message_id = get_in(message_params, ["replyId"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :sender])

      # ensure the message has been received by the mock
      assert_receive :received_message_to_process

      # test media fields
      assert message.media.url == audio_payload["url"] <> audio_payload["signature"]
      assert message.media.source_url == audio_payload["url"] <> audio_payload["signature"]

      # Sender should be stored into the db
      assert message.sender.phone ==
               get_in(message_params, ["mobile"])
    end

    test "Incoming video message should be stored in the database",
         setup_config = %{conn: conn} do
      video_payload =
        setup_config.media_payload
        |> Map.put("mime_type", "video/mp4")
        |> Map.put("caption", Faker.Lorem.sentence())

      message_params =
        setup_config.message_params
        |> put_in(["type"], "video")
        |> Map.put("video", Jason.encode!(video_payload))

      conn = post(conn, "/gupshup-enterprise", message_params)
      assert conn.halted
      bsp_message_id = get_in(message_params, ["replyId"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :sender])

      # ensure the message has been received by the mock
      assert_receive :received_message_to_process

      # test media fields
      assert message.media.caption == video_payload["caption"]
      assert message.media.url == video_payload["url"] <> video_payload["signature"]
      assert message.media.source_url == video_payload["url"] <> video_payload["signature"]

      # Sender should be stored into the db
      assert message.sender.phone ==
               get_in(setup_config.message_params, ["mobile"])
    end

    test "Incoming file message should be stored in the database", setup_config = %{conn: conn} do
      file_payload =
        setup_config.media_payload
        |> Map.put("mime_type", "application/pdf")
        |> Map.put("caption", Faker.Lorem.sentence())

      message_params =
        setup_config.message_params
        |> put_in(["type"], "document")
        |> Map.put("document", Jason.encode!(file_payload))

      conn = post(conn, "/gupshup-enterprise", message_params)
      assert conn.halted
      bsp_message_id = get_in(message_params, ["replyId"])

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:media, :sender])

      # ensure the message has been received by the mock
      assert_receive :received_message_to_process

      # test media fields
      assert message.media.caption == file_payload["caption"]
      assert message.media.url == file_payload["url"] <> file_payload["signature"]
      assert message.media.source_url == file_payload["url"] <> file_payload["signature"]

      # Sender should be stored into the db
      assert message.sender.phone ==
               get_in(message_params, ["mobile"])
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
        |> put_in(["type"], "location")

      %{message_params: message_params, location_payload: location_payload}
    end

    test "Incoming location message and contact's location should be stored in the database",
         setup_config = %{conn: conn} do
      message_params =
        setup_config.message_params
        |> Map.put("location", Jason.encode!(setup_config.location_payload))

      conn = post(conn, "/gupshup-enterprise", message_params)
      assert conn.halted

      # text_response(conn, 200)
      bsp_message_id = get_in(message_params, ["replyId"])

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
      assert location.latitude == setup_config.location_payload["latitude"]
    end
  end
end
