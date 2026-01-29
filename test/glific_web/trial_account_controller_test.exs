defmodule GlificWeb.API.V1.TrialAccountControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Contacts.Contact,
    Mails.MailLog,
    Partners.Organization,
    Repo,
    Seeds.SeedsDev,
    TrialUsers,
    Users.User
  }

  alias GlificWeb.API.V1.TrialAccountController

  @valid_phone "9876543210"
  @password "Secret1234!"

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()

    :ok
  end

  describe "trial/2" do
    setup do
      trial_org_1 = insert_trial_organization("trial1")
      trial_org_2 = insert_trial_organization("trial2")

      allocated_org =
        insert_trial_organization("allocated", %{
          trial_expiration_date: DateTime.utc_now() |> DateTime.add(10, :day)
        })

      trial_user = insert_trial_user(@valid_phone)

      valid_otp = PasswordlessAuth.generate_code(@valid_phone)

      %{
        trial_org_1: trial_org_1,
        trial_org_2: trial_org_2,
        allocated_org: allocated_org,
        trial_user: trial_user,
        valid_otp: valid_otp
      }
    end

    defp insert_trial_user(phone) do
      default_attrs = %{
        phone: phone,
        username: "Test User",
        email: "test_#{phone}@example.com",
        organization_name: "Test Organization",
        otp_entered: false
      }

      %TrialUsers{}
      |> TrialUsers.changeset(default_attrs)
      |> Repo.insert!()
    end

    test "successfully allocates a trial account with valid token", %{
      conn: conn,
      trial_org_1: trial_org_1,
      valid_otp: valid_otp
    } do
      params = %{
        "phone" => @valid_phone,
        "otp" => valid_otp,
        "username" => "Test User",
        "password" => @password
      }

      conn = TrialAccountController.trial(conn, params)
      response = json_response(conn, 200)

      assert response["success"] == true
      assert response["data"]["login_url"] == "https://#{trial_org_1.shortcode}.glific.com/login"

      updated_org = Repo.get!(Organization, trial_org_1.id, skip_organization_id: true)
      assert updated_org.trial_expiration_date != nil

      contact =
        Repo.get_by(Contact, [phone: @valid_phone, organization_id: trial_org_1.id],
          skip_organization_id: true
        )

      assert contact != nil
      assert contact.name == "Test User"

      user =
        Repo.get_by(User, [phone: @valid_phone, organization_id: trial_org_1.id],
          skip_organization_id: true
        )

      assert user != nil
      assert user.name == "Test User"
      assert user.contact_id == contact.id
      assert user.roles == [:admin]
    end

    test "sends emails to trial user and biz dev on successfully assigning trial account", %{
      conn: conn,
      trial_org_1: trial_org_1,
      valid_otp: valid_otp
    } do
      params = %{
        "phone" => @valid_phone,
        "otp" => valid_otp,
        "username" => "Test User",
        "password" => @password
      }

      conn = TrialAccountController.trial(conn, params)
      response = json_response(conn, 200)

      assert response["success"] == true
      assert response["data"]["login_url"] == "https://#{trial_org_1.shortcode}.glific.com/login"

      assert [_ | _] =
               MailLog.list_mail_logs(
                 %{organization_id: trial_org_1.id, category: "trial_user_welcome"},
                 skip_organization_id: true
               )

      assert [_ | _] =
               MailLog.list_mail_logs(
                 %{organization_id: trial_org_1.id, category: "new_trial_account_allocated"},
                 skip_organization_id: true
               )
    end

    test "returns error with invalid OTP", %{conn: conn} do
      params = %{
        "phone" => @valid_phone,
        "otp" => "wrong_otp",
        "username" => "Test User",
        "password" => @password
      }

      conn = TrialAccountController.trial(conn, params)

      assert json_response(conn, 400) == %{
               "success" => false,
               "error" => "Invalid OTP"
             }
    end

    test "returns error when no trial accounts are available", %{
      conn: conn,
      trial_org_1: trial_org_1,
      trial_org_2: trial_org_2,
      valid_otp: valid_otp
    } do
      expiration_date = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(14, :day)

      Enum.each([trial_org_1, trial_org_2], fn org ->
        Organization
        |> Repo.get!(org.id, skip_organization_id: true)
        |> Ecto.Changeset.change(%{
          trial_expiration_date: expiration_date
        })
        |> Repo.update!(skip_organization_id: true)
      end)

      params = %{
        "phone" => @valid_phone,
        "otp" => valid_otp,
        "username" => "Test User",
        "password" => @password
      }

      conn = TrialAccountController.trial(conn, params)

      assert json_response(conn, 200) == %{
               "success" => false,
               "error" =>
                 "Thank you for your interest in exploring Glific.

          Apologies, at the moment, all our trial accounts are currently in use. Our Sales team will reach out to you shortly to discuss alternative options."
             }
    end

    test "returns error when contact creation fails", %{conn: conn, valid_otp: valid_otp} do
      params = %{
        "phone" => @valid_phone,
        "otp" => valid_otp,
        "username" => nil,
        "password" => @password
      }

      conn = TrialAccountController.trial(conn, params)

      response = json_response(conn, 500)

      assert response == %{
               "success" => false,
               "error" => "Something went wrong"
             }
    end

    test "rolls back organization allocation when contact creation fails", %{
      conn: conn,
      trial_org_1: trial_org_1,
      valid_otp: valid_otp
    } do
      org_before = Repo.get!(Organization, trial_org_1.id, skip_organization_id: true)
      assert org_before.trial_expiration_date == nil

      params = %{
        "phone" => @valid_phone,
        "otp" => valid_otp,
        "username" => nil,
        "password" => @password
      }

      conn = TrialAccountController.trial(conn, params)

      response = json_response(conn, 500)

      assert response == %{
               "success" => false,
               "error" => "Something went wrong"
             }

      org_after = Repo.get!(Organization, trial_org_1.id, skip_organization_id: true)

      assert org_after.trial_expiration_date == nil,
             "Organization should not be allocated when transaction fails"

      # Verify no contact was created
      contact =
        Repo.get_by(Contact, [phone: @valid_phone, organization_id: trial_org_1.id],
          skip_organization_id: true
        )

      assert contact == nil, "Contact should not exist when transaction fails"

      # Verify no user was created
      user =
        Repo.get_by(User, [phone: @valid_phone, organization_id: trial_org_1.id],
          skip_organization_id: true
        )

      assert user == nil, "User should not exist when transaction fails"
    end

    test "rolls back organization allocation when user creation fails", %{
      conn: conn,
      trial_org_1: trial_org_1,
      valid_otp: valid_otp
    } do
      org_before = Repo.get!(Organization, trial_org_1.id, skip_organization_id: true)
      assert org_before.trial_expiration_date == nil

      params = %{
        "phone" => @valid_phone,
        "otp" => valid_otp,
        "username" => "Test User",
        "password" => "weak"
      }

      conn = TrialAccountController.trial(conn, params)

      response = json_response(conn, 500)

      assert response == %{
               "success" => false,
               "error" => "Something went wrong"
             }

      org_after = Repo.get!(Organization, trial_org_1.id, skip_organization_id: true)

      assert org_after.trial_expiration_date == nil,
             "Organization should not be allocated when transaction fails"

      contact =
        Repo.get_by(Contact, [phone: @valid_phone, organization_id: trial_org_1.id],
          skip_organization_id: true
        )

      assert contact == nil, "Contact should not exist when transaction rolls back"

      user =
        Repo.get_by(User, [phone: @valid_phone, organization_id: trial_org_1.id],
          skip_organization_id: true
        )

      assert user == nil, "User should not exist when transaction fails"
    end
  end

  @spec insert_trial_organization(String.t(), map()) :: Organization.t()
  defp insert_trial_organization(shortcode, attrs \\ %{}) do
    default_attrs = %{
      name: "Trial Org #{shortcode}",
      shortcode: shortcode,
      email: "trial_#{shortcode}@example.com",
      is_trial_org: true,
      trial_expiration_date: nil,
      bsp_id: 1,
      status: :inactive,
      timezone: "Asia/Kolkata",
      default_language_id: 1,
      active_language_ids: [1]
    }

    attrs = Map.merge(default_attrs, attrs)

    org =
      %Organization{}
      |> Organization.changeset(attrs)
      |> Repo.insert!()

    SeedsDev.seed_roles(org)

    org
  end
end
