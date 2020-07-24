defmodule GlificWeb.API.V1.RegistrationControllerTest do
  use GlificWeb.ConnCase

  @password "secret1234"

  setup do
    default_provider = Glific.SeedsDev.seed_providers()
    Glific.SeedsDev.seed_organizations(default_provider)
    Glific.SeedsDev.seed_contacts()
    :ok
  end

  describe "create/2" do
    @valid_params %{
      "user" => %{
        "phone" => "+919820198765",
        "name" => "John Doe",
        "password" => @password,
        "password_confirmation" => @password
      }
    }

    test "with valid params", %{conn: conn} do
      {:ok, receiver} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: "Default receiver"})

      {:ok, otp} = PasswordlessAuth.create_and_send_verification_code(receiver.phone)

      valid_params = %{
        "user" => %{
          "phone" => receiver.phone,
          "name" => receiver.name,
          "password" => @password,
          "password_confirmation" => @password,
          "otp" => otp
        }
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :create, valid_params))

      assert json = json_response(conn, 200)
      assert json["data"]["access_token"]
      assert json["data"]["renewal_token"]
      assert json["data"]["token_expiry_time"]

      # We will tag the user as a contact tag
      {:ok, staff_tag} = Glific.Repo.fetch_by(Glific.Tags.Tag, %{label: "Staff"})
      {:ok, contact} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{phone: receiver.phone})

      assert {:ok, _contact_tag} =
               Glific.Repo.fetch_by(Glific.Tags.ContactTag, %{
                 contact_id: contact.id,
                 tag_id: staff_tag.id
               })
    end

    test "with wrong otp", %{conn: conn} do
      invalid_params =
        @valid_params
        |> put_in(["user", "otp"], "wrong_otp")

      conn = post(conn, Routes.api_v1_registration_path(conn, :create, invalid_params))

      assert json = json_response(conn, 500)
      assert json["error"]["status"] == 500
    end

    test "with invalid params", %{conn: conn} do
      {:ok, receiver} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: "Default receiver"})

      {:ok, otp} = PasswordlessAuth.create_and_send_verification_code(receiver.phone)

      invalid_params = %{
        "user" => %{
          "phone" => "incorrect_phone",
          "name" => receiver.name,
          "password" => @password,
          "otp" => otp
        }
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :create, invalid_params))

      assert json = json_response(conn, 500)

      assert json["error"]["message"] == "Couldn't create user"
      assert json["error"]["status"] == 500
      # assert json["error"]["errors"]["phone"] == ["has invalid format"]
    end
  end

  describe "send_otp/2" do
    test "send otp", %{conn: conn} do
      {:ok, receiver} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: "Default receiver"})
      Glific.Contacts.contact_opted_in(receiver.phone, DateTime.utc_now())

      valid_params = %{"user" => %{"phone" => receiver.phone}}

      conn = post(conn, Routes.api_v1_registration_path(conn, :send_otp, valid_params))

      assert json = json_response(conn, 200)
      assert get_in(json, ["data", "phone"]) == valid_params["user"]["phone"]
    end

    test "send otp to invalid contact", %{conn: conn} do
      phone = "invalid contact"
      invalid_params = %{"user" => %{"phone" => phone}}

      conn = post(conn, Routes.api_v1_registration_path(conn, :send_otp, invalid_params))

      assert json = json_response(conn, 400)
      assert get_in(json, ["error", "message"]) == "Cannot send the otp to #{phone}"
    end

    test "send otp to existing user will return an error", %{conn: conn} do
      [user | _] = Glific.Users.list_users()
      phone = user.phone
      invalid_params = %{"user" => %{"phone" => phone}}

      conn = post(conn, Routes.api_v1_registration_path(conn, :send_otp, invalid_params))

      assert json = json_response(conn, 400)
      assert get_in(json, ["error", "message"]) == "Cannot send the otp to #{phone}"
    end

    test "send otp to optout contact will return an error", %{conn: conn} do
      {:ok, receiver} = Glific.Repo.fetch_by(Glific.Contacts.Contact, %{name: "Default receiver"})
      Glific.Contacts.contact_opted_out(receiver.phone, DateTime.utc_now())
      invalid_params = %{"user" => %{"phone" => receiver.phone}}

      conn = post(conn, Routes.api_v1_registration_path(conn, :send_otp, invalid_params))

      assert json = json_response(conn, 400)

      assert get_in(json, ["error", "message"]) ==
               "Cannot send the otp to #{receiver.phone}"
    end
  end
end
