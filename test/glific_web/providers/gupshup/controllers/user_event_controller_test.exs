defmodule GlificWeb.Providers.Gupshup.Controllers.UserEventControllerTest do
  use GlificWeb.ConnCase

  alias Faker.Phone

  @user_event_request_params %{
    "app" => "TidesTestApi",
    "payload" => %{
      "phone" => Phone.EnUs.phone(),
      "type" => "opted-in"
    },
    "timestamp" => 1_592_559_772_322,
    "type" => "user-event",
    "version" => 2
  }

  setup do
    default_provider = Glific.SeedsDev.seed_providers()
    Glific.SeedsDev.seed_organizations(default_provider)
    Glific.SeedsDev.seed_contacts()
    Glific.SeedsDev.seed_messages()
    :ok
  end

  describe "handler" do
    test "handler should return nil data", %{conn: conn} do
      params = put_in(@user_event_request_params, ["payload", "type"], "not defined")
      conn = post(conn, "/gupshup", params)
      assert json_response(conn, 200) == nil
    end
  end

  describe "opted_in" do
    setup do
      contact_payload = %{
        "phone" => Phone.EnUs.phone(),
        "type" => "opted-in"
      }

      message_params =
        @user_event_request_params
        |> put_in(["payload"], contact_payload)

      %{message_params: message_params}
    end

    test "optin_time and status should be updated", setup_config = %{conn: conn} do
      phone = get_in(setup_config.message_params, ["payload", "phone"])
      conn = post(conn, "/gupshup", setup_config.message_params)
      json_response(conn, 200)
      {:ok, contact} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{phone: phone})
      assert contact.optin_time != nil
      assert contact.status == :valid
    end
  end

  describe "opted_out" do
    setup do
      contact_payload = %{
        "phone" => Phone.EnUs.phone(),
        "type" => "opted-out"
      }

      message_params =
        @user_event_request_params
        |> put_in(["payload"], contact_payload)

      %{message_params: message_params}
    end

    test "optout_time and status should be updated", setup_config = %{conn: conn} do
      phone = get_in(setup_config.message_params, ["payload", "phone"])
      conn = post(conn, "/gupshup", setup_config.message_params)
      json_response(conn, 200)
      {:ok, contact} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{phone: phone})
      assert contact.optout_time != nil
      assert contact.status == :invalid
    end
  end
end
