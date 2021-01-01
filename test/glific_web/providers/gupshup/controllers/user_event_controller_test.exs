defmodule GlificWeb.Providers.Gupshup.Controllers.UserEventControllerTest do
  use GlificWeb.ConnCase

  alias Faker.Phone

  alias Glific.{
    Contacts.Contact,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  @user_event_request_params %{
    "payload" => %{
      "phone" => Phone.EnUs.phone(),
      "type" => "opted-in"
    },
    "timestamp" => 1_592_559_772_322,
    "type" => "user-event",
    "version" => 2
  }

  defp get_params(conn, default_params) do
    organization = Partners.organization(conn.assigns[:organization_id])
    app_name = organization.services["bsp"].secrets["app_name"]
    Map.merge(default_params, %{"app" => app_name})
  end

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  describe "handler" do
    test "handler should return nil data", %{conn: conn} do
      updated_params = get_params(conn, @user_event_request_params)
      params = put_in(updated_params, ["payload", "type"], "not defined")
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
      params = get_params(conn, setup_config.message_params)
      conn = post(conn, "/gupshup", params)
      json_response(conn, 200)

      {:ok, contact} =
        Repo.fetch_by(Contact, %{phone: phone, organization_id: conn.assigns[:organization_id]})

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
      params = get_params(conn, setup_config.message_params)
      phone = get_in(setup_config.message_params, ["payload", "phone"])
      conn = post(conn, "/gupshup", params)
      json_response(conn, 200)

      {:ok, contact} =
        Repo.fetch_by(Contact, %{phone: phone, organization_id: conn.assigns[:organization_id]})

      assert contact.optout_time != nil
      assert contact.status == :invalid
    end
  end
end
