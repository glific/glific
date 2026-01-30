defmodule GlificWeb.API.V1.TrialUsersControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Repo,
    TrialUsers
  }

  alias GlificWeb.API.V1.TrialUsersController

  import Mock

  @mock_otp_code "123456"

  describe "create_trial_user/2" do
    test "creates a new trial user and sends OTP with valid data", %{conn: conn} do
      params = %{
        "username" => "new_user",
        "email" => "newuser@example.com",
        "phone" => "+919719266288",
        "organization_name" => "New Org"
      }

      result = TrialUsersController.create_trial_user(conn, params)

      assert json_response(result, 200) == %{
               "data" => %{
                 "message" => "OTP sent successfully to newuser@example.com"
               }
             }

      assert Repo.get_by(TrialUsers, %{email: "newuser@example.com"}, skip_organization_id: true)
    end

    test "resends OTP when user exists but OTP not verified", %{conn: conn} do
      {:ok, trial_user} =
        TrialUsers.create_trial_user(%{
          username: "john_doe",
          email: "john@example.com",
          phone: "919719266288",
          organization_name: "Test Org",
          otp_entered: false
        })

      params = %{
        "username" => trial_user.username,
        "email" => trial_user.email,
        "phone" => trial_user.phone,
        "organization_name" => trial_user.organization_name
      }

      result = TrialUsersController.create_trial_user(conn, params)

      assert json_response(result, 200) == %{
               "data" => %{
                 "message" => "OTP sent successfully to #{trial_user.email}"
               }
             }

      users =
        TrialUsers
        |> Repo.all(skip_organization_id: true)
        |> Enum.filter(fn u -> u.email == trial_user.email end)

      assert length(users) == 1
    end

    test "returns error when phone already exists with different email", %{conn: conn} do
      {:ok, _existing_user} =
        TrialUsers.create_trial_user(%{
          username: "existing",
          email: "existing2@example.com",
          phone: "919719266288",
          organization_name: "Existing Org",
          otp_entered: true
        })

      params = %{
        "username" => "new_user",
        "email" => "different@example.com",
        "phone" => "919719266288",
        "organization_name" => "New Org"
      }

      result = TrialUsersController.create_trial_user(conn, params)

      response = json_response(result, 200)
      assert response["success"] == false
      assert response["error"] == "Email or phone already registered"
    end

    test "returns error when trial user creation fails due to validation", %{conn: conn} do
      params = %{
        "username" => "test_user",
        "email" => "test",
        "phone" => "+919719266288",
        "organization_name" => "Test Org"
      }

      result = TrialUsersController.create_trial_user(conn, params)

      assert json_response(result, 400) == %{
               "error" => "Failed to create trial account",
               "success" => false
             }
    end

    test "returns error when email sending fails", %{conn: conn} do
      params = %{
        "username" => "test_user",
        "email" => "test@example.com",
        "phone" => "+919719266288",
        "organization_name" => "Test Org"
      }

      with_mocks([
        {PasswordlessAuth, [], [generate_code: fn _phone -> @mock_otp_code end]},
        {Glific.Mails.TrialAccountMail, [],
         [
           otp_verification_mail: fn _org, _email, _code, _username ->
             %Swoosh.Email{}
           end
         ]},
        {Glific.Communications.Mailer, [],
         [send: fn _email, _opts -> {:error, "SMTP connection failed"} end]}
      ]) do
        result = TrialUsersController.create_trial_user(conn, params)

        assert json_response(result, 500) == %{
                 "error" => "Failed to send OTP email",
                 "success" => false
               }
      end
    end

    test "returns error when phone number is not valid", %{conn: conn} do
      params = %{
        "username" => "new_user",
        "email" => "newuser@example.com",
        "phone" => "5555555555",
        "organization_name" => "New Org"
      }

      result = TrialUsersController.create_trial_user(conn, params)

      response = json_response(result, 400)
      assert response["success"] == false

      assert response["error"] ==
               "Phone number is not valid. Please enter the phone number with country code, without the + symbol."
    end
  end
end
