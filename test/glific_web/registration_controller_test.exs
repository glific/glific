defmodule GlificWeb.API.V1.RegistrationControllerTest do
  use GlificWeb.ConnCase

  alias GlificWeb.API.V1.RegistrationController

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Fixtures,
    Partners.Saas,
    Repo,
    Seeds.SeedsDev,
    Users
  }

  @password "Secret1234!"

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    Fixtures.set_bsp_partner_tokens()
    Fixtures.otp_hsm_fixture()
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
      receiver = Fixtures.contact_fixture()
      {:ok, otp} = RegistrationController.create_and_send_verification_code(receiver)

      valid_params = %{
        "user" => %{
          "phone" => receiver.phone,
          "name" => receiver.name,
          "password" => @password,
          "otp" => otp
        }
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :create, valid_params))

      assert json = json_response(conn, 200)
      assert json["data"]["access_token"]
      assert json["data"]["renewal_token"]
      assert json["data"]["token_expiry_time"]

      {:ok, _contact} =
        Repo.fetch_by(Contact, %{
          phone: receiver.phone,
          organization_id: conn.assigns[:organization_id]
        })
    end

    test "with password less than minimum characters should give error",
         %{conn: conn} do
      receiver = Fixtures.contact_fixture()

      {:ok, otp} = RegistrationController.create_and_send_verification_code(receiver)

      valid_params = %{
        "user" => %{
          "phone" => receiver.phone,
          "name" => receiver.name,
          "password" => "Secret12",
          "otp" => otp
        }
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :create, valid_params))

      assert json = json_response(conn, 500)

      assert json["error"]["status"] == 500

      assert json["error"]["errors"] ==
               %{
                 "password" => [
                   "Not enough special characters (only 0 instead of at least 1)",
                   "Password is too short!"
                 ]
               }
    end

    test "with wrong otp", %{conn: conn} do
      receiver = Fixtures.contact_fixture()

      invalid_params =
        @valid_params
        |> put_in(["user", "phone"], receiver.phone)
        |> put_in(["user", "otp"], "wrong_otp")

      conn = post(conn, Routes.api_v1_registration_path(conn, :create, invalid_params))

      assert json = json_response(conn, 500)
      assert json["error"]["status"] == 500
    end

    test "with invalid params", %{conn: conn} do
      receiver = Fixtures.contact_fixture()

      {:ok, otp} = RegistrationController.create_and_send_verification_code(receiver)

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
    end
  end

  describe "send_otp/2" do
    setup do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            body:
              "{\n  \"success\": true,\n  \"challenge_ts\": \"2023-01-09T04:58:39Z\",\n  \"hostname\": \"glific.test\",\n  \"score\": 0.9,\n  \"action\": \"register\"\n}",
            status: 200
          }

        %{method: :get, url: "https://partner.gupshup.io/partner/app/Glific42/wallet/balance"} ->
          %Tesla.Env{
            status: 200,
            body:
              "{\"status\":\"success\",\"walletResponse\":{\"currency\":\"USD\",\"currentBalance\":1.787,\"overDraftLimit\":-20.0}}"
          }
      end)

      :ok
    end

    test "send otp successfully from NGO bot when balance is greater than 0", %{conn: conn} do
      valid_params = %{
        "user" => %{"phone" => "918456732456", "registration" => "true", "token" => "some_token"}
      }

      conn =
        post(conn, Routes.api_v1_registration_path(conn, :send_otp, valid_params))

      assert json = json_response(conn, 200)
      assert get_in(json, ["data", "phone"]) == valid_params["user"]["phone"]
    end

    test "send otp to invalid contact", %{conn: conn} do
      phone = nil

      invalid_params = %{
        "user" => %{"phone" => phone, "registration" => "true", "token" => "some_token"}
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :send_otp, invalid_params))

      assert json = json_response(conn, 400)
      assert get_in(json, ["error", "message"]) == "Cannot send the otp to #{phone}"
    end

    test "send otp to existing user will return an error", %{conn: conn} do
      [user | _] = Users.list_users(%{filter: %{organization_id: conn.assigns[:organization_id]}})
      phone = user.phone

      invalid_params = %{
        "user" => %{"phone" => phone, "registration" => "true", "token" => "some_token"}
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :send_otp, invalid_params))

      assert json = json_response(conn, 400)

      assert get_in(json, ["error", "message"]) ==
               "Account with phone number #{phone} already exists"
    end

    test "send otp to the non existing contact should get an error message", %{conn: conn} do
      phone = "912345375758"

      invalid_params = %{
        "user" => %{"phone" => phone, "registration" => "false"}
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :send_otp), invalid_params)

      assert json = json_response(conn, 400)

      assert get_in(json, ["error", "message"]) ==
               "Account with phone number #{phone} does not exist"
    end

    test "Handle errors while sending otp when registration is false", %{conn: conn} do
      receiver = Fixtures.contact_fixture()

      Contacts.contact_opted_in(
        %{phone: receiver.phone},
        receiver.organization_id,
        DateTime.utc_now()
      )

      {:ok, receiver} = Contacts.update_contact(receiver, %{status: :invalid})
      Fixtures.user_fixture(%{phone: receiver.phone})

      invalid_params = %{
        "user" => %{"phone" => receiver.phone, "registration" => "false"}
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :send_otp), invalid_params)

      assert json = json_response(conn, 400)

      assert get_in(json, ["error", "message"]) ==
               "Cannot send the otp to #{receiver.phone}"
    end

    test "send otp to optout contact will optin the contact again", %{conn: conn} do
      receiver = Fixtures.contact_fixture()

      Contacts.contact_opted_out(receiver.phone, receiver.organization_id, DateTime.utc_now())

      invalid_params = %{
        "user" => %{"phone" => receiver.phone, "registration" => "true", "token" => "some_token"}
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :send_otp, invalid_params))

      assert json = json_response(conn, 400)
      assert get_in(json, ["error", "message"]) == "Cannot send the otp to #{receiver.phone}"
    end

    test "send otp from Glific when NGO's wallet balance is less than 0", %{conn: conn} do
      org = Fixtures.organization_fixture(%{shortcode: "neworg"})

      conn = assign(conn, :organization_id, org.id)

      valid_params = %{
        "user" => %{"phone" => "918456732456", "registration" => "true", "token" => "some_token"}
      }

      glific_org_id = Saas.organization_id()

      Tesla.Mock.mock(fn
        %{
          method: :post
        } ->
          %Tesla.Env{
            body:
              "{\n  \"success\": true,\n  \"challenge_ts\": \"2023-01-09T04:58:39Z\",\n  \"hostname\": \"glific.test\",\n  \"score\": 0.9,\n  \"action\": \"register\"\n}",
            status: 200
          }

        %{method: :get, url: url} = env ->
          if String.contains?(url, "/wallet/balance") do
            %Tesla.Env{
              status: 200,
              body:
                "{\"status\":\"success\",\"walletResponse\":{\"currency\":\"USD\",\"currentBalance\":-1.787,\"overDraftLimit\":-20.0}}"
            }
          else
            env
          end
      end)

      conn =
        post(conn, Routes.api_v1_registration_path(conn, :send_otp, valid_params))

      assert json = json_response(conn, 200)
      assert get_in(json, ["data", "phone"]) == valid_params["user"]["phone"]

      contact =
        Repo.get_by!(Contacts.Contact,
          phone: valid_params["user"]["phone"]
        )

      # it used the fallback org
      assert contact.organization_id == glific_org_id
      assert contact.organization_id != org.id
    end

    @tag :fgt
    test "send otp with registration 'false' flag when NGO's wallet balance is less than 0", %{
      conn: conn
    } do
      org = Fixtures.organization_fixture(%{shortcode: "neworg"})

      conn = assign(conn, :organization_id, org.id)

      # create a user for a contact
      receiver = Fixtures.contact_fixture(%{organization_id: org.id, phone: "918456732452"})

      Contacts.contact_opted_in(
        %{phone: receiver.phone},
        receiver.organization_id,
        DateTime.utc_now()
      )

      {:ok, _user} =
        %{
          "phone" => receiver.phone,
          "name" => receiver.name,
          "password" => @password,
          "password_confirmation" => @password,
          "contact_id" => receiver.id,
          "organization_id" => receiver.organization_id
        }
        |> Users.create_user()

      valid_params = %{
        "user" => %{"phone" => "918456732452", "registration" => "false", "token" => "some_token"}
      }

      glific_org_id = Saas.organization_id()

      Tesla.Mock.mock(fn
        %{
          method: :post
        } ->
          %Tesla.Env{
            body:
              "{\n  \"success\": true,\n  \"challenge_ts\": \"2023-01-09T04:58:39Z\",\n  \"hostname\": \"glific.test\",\n  \"score\": 0.9,\n  \"action\": \"register\"\n}",
            status: 200
          }

        %{method: :get, url: url} = env ->
          if String.contains?(url, "/wallet/balance") do
            %Tesla.Env{
              status: 200,
              body:
                "{\"status\":\"success\",\"walletResponse\":{\"currency\":\"USD\",\"currentBalance\":-1.787,\"overDraftLimit\":-20.0}}"
            }
          else
            env
          end
      end)

      conn =
        post(conn, Routes.api_v1_registration_path(conn, :send_otp, valid_params))

      assert json = json_response(conn, 200)
      assert get_in(json, ["data", "phone"]) == valid_params["user"]["phone"]

      contact =
        Repo.get_by!(Contacts.Contact,
          phone: valid_params["user"]["phone"]
        )

      # it used the fallback org
      assert contact.organization_id == glific_org_id
      assert contact.organization_id != org.id
    end

    test "send otp with registration 'false' flag to existing user should succeed", %{conn: conn} do
      # create a user for a contact
      receiver = Fixtures.contact_fixture()

      Contacts.contact_opted_in(
        %{phone: receiver.phone},
        receiver.organization_id,
        DateTime.utc_now()
      )

      {:ok, user} =
        %{
          "phone" => receiver.phone,
          "name" => receiver.name,
          "password" => @password,
          "password_confirmation" => @password,
          "contact_id" => receiver.id,
          "organization_id" => Fixtures.get_org_id()
        }
        |> Users.create_user()

      valid_params = %{
        "user" => %{
          "phone" => user.phone,
          "registration" => "false",
          "token" => "some_token"
        }
      }

      conn =
        post(conn, Routes.api_v1_registration_path(conn, :send_otp, valid_params))

      assert _json = json_response(conn, 200)
    end

    test "send otp when Gupshup is not active", %{conn: conn} do
      org = Fixtures.organization_fixture(%{shortcode: "neworg"})

      conn = assign(conn, :organization_id, org.id)

      valid_params = %{
        "user" => %{"phone" => "919999999999", "registration" => "true", "token" => "some_token"}
      }

      glific_org_id = Saas.organization_id()

      org =
        Fixtures.organization_fixture(%{
          shortcode: "shortcode"
        })

      Tesla.Mock.mock(fn
        %{
          method: :post
        } ->
          %Tesla.Env{
            body:
              "{\n  \"success\": true,\n  \"challenge_ts\": \"2023-01-09T04:58:39Z\",\n  \"hostname\": \"glific.test\",\n  \"score\": 0.9,\n  \"action\": \"register\"\n}",
            status: 200
          }

        %{method: :get, url: url} = _env ->
          if String.contains?(url, "/wallet/balance") do
            %Tesla.Env{
              status: 500,
              body:
                "{\"status\":\"error\",\"message\":\"Unauthorised access to the resource. Please review request parameters and headers and retry\"}"
            }
          end
      end)

      _org = Map.put(org, :services, Map.put(org.services, "bsp", nil))

      conn = post(conn, Routes.api_v1_registration_path(conn, :send_otp, valid_params))
      assert json = json_response(conn, 200)
      assert get_in(json, ["data", "phone"]) == valid_params["user"]["phone"]

      contact =
        Repo.get_by!(Contacts.Contact,
          phone: valid_params["user"]["phone"]
        )

      # it used the fallback org
      assert contact.organization_id == glific_org_id
      assert contact.organization_id != org.id
    end
  end

  describe "reset_password/2" do
    @password "Secret12345!"
    @new_password "Not12345678!"

    def user_fixture do
      # create a user for a contact
      receiver = Fixtures.contact_fixture()

      valid_user_attrs = %{
        "phone" => receiver.phone,
        "name" => receiver.name,
        "password" => @password,
        "password_confirmation" => @password,
        "contact_id" => receiver.id,
        "organization_id" => Fixtures.get_org_id()
      }

      {:ok, user} =
        valid_user_attrs
        |> Users.create_user()

      user
    end

    test "with valid params", %{conn: conn} do
      user = user_fixture() |> Repo.preload([:contact])

      # reset password of a user
      {:ok, otp} = RegistrationController.create_and_send_verification_code(user.contact)

      valid_params = %{
        "user" => %{
          "phone" => user.phone,
          "password" => @new_password,
          "otp" => otp
        }
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :reset_password, valid_params))
      assert json = json_response(conn, 200)
      assert json["data"]["access_token"]
      assert json["data"]["renewal_token"]
      assert json["data"]["token_expiry_time"]
    end

    test "with wrong otp", %{conn: conn} do
      user = user_fixture()

      invalid_params = %{
        "user" => %{
          "phone" => user.phone,
          "password" => @new_password,
          "otp" => "incorrect otp"
        }
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :reset_password, invalid_params))

      assert json = json_response(conn, 500)
      assert json["error"]["status"] == 500
    end

    test "with incorrect phone number", %{conn: conn} do
      user = user_fixture() |> Repo.preload([:contact])

      {:ok, otp} = RegistrationController.create_and_send_verification_code(user.contact)

      invalid_params = %{
        "user" => %{
          "phone" => "incorrect_phone",
          "password" => @new_password,
          "otp" => otp
        }
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :create, invalid_params))

      assert json = json_response(conn, 500)
      assert json["error"]["status"] == 500
    end

    test "with password less than 8 characters", %{conn: conn} do
      user = user_fixture() |> Repo.preload([:contact])

      # reset password of user
      {:ok, otp} = RegistrationController.create_and_send_verification_code(user.contact)

      valid_params = %{
        "user" => %{
          "phone" => user.phone,
          "password" => "1234567",
          "otp" => otp
        }
      }

      conn = post(conn, Routes.api_v1_registration_path(conn, :reset_password, valid_params))

      assert json = json_response(conn, 500)
      assert json["error"]["status"] == 500
    end
  end

  describe "rate limit tests" do
    @password "Secret12345!"
    @max_unauth_requests 50

    test "with invalid request", %{conn: conn} do
      receiver = Fixtures.contact_fixture()

      valid_user_attrs = %{
        "phone" => receiver.phone,
        "name" => receiver.name,
        "password" => @password,
        "password_confirmation" => @password,
        "contact_id" => receiver.id,
        "organization_id" => Fixtures.get_org_id()
      }

      {:ok, user} =
        valid_user_attrs
        |> Users.create_user()

      invalid_params = %{
        "user" => %{
          "phone" => user.phone,
          "password" => @new_password,
          "otp" => "incorrect otp"
        }
      }

      for _i <- 0..@max_unauth_requests,
          do: post(conn, Routes.api_v1_registration_path(conn, :reset_password, invalid_params))

      conn = post(conn, Routes.api_v1_registration_path(conn, :reset_password, invalid_params))

      assert conn.status == 429
      assert conn.resp_body == "Rate limit exceeded"
    end
  end
end
