defmodule GlificWeb.MessageControllerTest do
  use GlificWeb.ConnCase

  alias Glific.Messages.Message

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
    Glific.Seeds.seed_contacts()
    Glific.Seeds.seed_messages()
    :ok
  end

  describe "handler" do
    test "handler should return nil data", %{conn: conn} do
      conn = post(conn, "/gupshup", @message_request_params)
      assert json_response(conn, 200) == nil
    end
  end

  describe "text" do

    setup do
      message_body = "Inbound Message"
      message_params =
          put_in(@message_request_params, ["payload", "payload", "text"], message_body)
          |> put_in(["payload", "type"], "text")
          |> put_in(["payload", "id"], Faker.String.base64(36))
          |> put_in(["payload", "id"], Faker.String.base64(36))
        %{message_params: message_params, message_body: message_body}
    end


    test "Incoming text message should be stored in the database", %{conn: conn, message_params: message_params, message_body: message_body } do
      conn =  post(conn, "/gupshup", message_params)
      json_response(conn, 200)
      {:ok, message} = Glific.Repo.fetch_by(Message, %{body: message_body})
      message = Glific.Repo.preload(message, [:receiver, :sender, :media])

      # Provider message id should be updated
      assert message.provider_message_id == get_in(message_params, ["payload", "id"])
      assert message.provider_status == :delivered
      assert message.flow == :inbound

      # Sender should be stored into the db
      assert message.sender.phone == get_in(message_params, ["payload", "sender", "phone"])
    end
  end



  # describe "image" do
  #   test "Incoming media message should be stored in the database", %{conn: conn} do
  #     message_body = "Inbound Message"
  #     message_params =
  #         put_in(@message_request_params, ["payload", "payload", "text"], message_body)
  #         |> put_in(["payload", "type"], "image")
  #         |> put_in(["payload", "id"], Faker.String.base64(36))

  #     conn =  post(conn, "/gupshup", message_params)
  #     json_response(conn, 200)
  #     {:ok, message} = Glific.Repo.fetch_by(Message, %{body: message_body})
  #     message = Glific.Repo.preload(message, [:receiver, :sender, :media])

  #     # Provider message id should be updated
  #     assert message.provider_message_id == get_in(message_params, ["payload", "id"])
  #     assert message.provider_status == :delivered
  #     assert message.flow == :inbound

  #     # Sender should be stored into the db
  #     assert message.sender.phone == get_in(message_params, ["payload", "sender", "phone"])
  #   end
  # end

  describe "file" do
  end

  describe "audio" do
  end

  describe "video" do
  end
end
