defmodule GlificWeb.API.V1.TrialAccountControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Contacts.Contact,
    Partners.Organization,
    Repo,
    Seeds.SeedsDev,
    Users.User
  }

  alias GlificWeb.API.V1.TrialAccountController

  @valid_token "test-trial-token-12345"
  @valid_phone "9876543210"
  @password "Secret1234!"

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()

    Application.put_env(:glific, TrialAccountController, trial_account_token: @valid_token)

    on_exit(fn ->
      Application.delete_env(:glific, TrialAccountController)
    end)

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

      valid_otp = PasswordlessAuth.generate_code(@valid_phone)

      %{
        trial_org_1: trial_org_1,
        trial_org_2: trial_org_2,
        allocated_org: allocated_org,
        valid_otp: valid_otp
      }
    end

    test "successfully allocates a trial account with valid token", %{
      conn: conn,
      trial_org_1: trial_org_1,
      valid_otp: valid_otp
    } do
      params = %{
        "phone" => @valid_phone,
        "otp" => valid_otp,
        "name" => "Test User",
        "password" => @password
      }

      conn =
        conn
        |> put_req_header("x-api-key", @valid_token)

      conn = TrialAccountController.trial(conn, params)
      response = json_response(conn, 200)

      assert response["success"] == true
      assert response["data"]["login_url"] == "https://#{trial_org_1.shortcode}.glific.com"

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

    test "returns error with invalid OTP", %{conn: conn} do
      params = %{
        "phone" => @valid_phone,
        "otp" => "wrong_otp",
        "name" => "Test User",
        "password" => @password
      }

      conn =
        conn
        |> put_req_header("x-api-key", @valid_token)

      conn = TrialAccountController.trial(conn, params)

      assert json_response(conn, 200) == %{
               "success" => false,
               "error" => "Invalid OTP"
             }
    end

    test "returns error with invalid API token", %{conn: conn, valid_otp: valid_otp} do
      params = %{
        "phone" => @valid_phone,
        "otp" => valid_otp,
        "name" => "Test User",
        "password" => @password
      }

      conn =
        conn
        |> put_req_header("x-api-key", "invalid-token")

      conn = TrialAccountController.trial(conn, params)

      assert json_response(conn, 401) == %{
               "success" => false,
               "error" => "Invalid API token"
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
        "name" => "Test User",
        "password" => @password
      }

      conn =
        conn
        |> put_req_header("x-api-key", @valid_token)

      conn = TrialAccountController.trial(conn, params)

      assert json_response(conn, 200) == %{
               "success" => false,
               "error" => "No trial accounts available at the moment"
             }
    end

    test "returns error when contact creation fails", %{conn: conn, valid_otp: valid_otp} do
      params = %{
        "phone" => @valid_phone,
        "otp" => valid_otp,
        # This will cause contact creation to fail
        "name" => nil,
        "password" => @password
      }

      conn =
        conn
        |> put_req_header("x-api-key", @valid_token)

      conn = TrialAccountController.trial(conn, params)

      response = json_response(conn, 200)

      assert response["success"] == false
      assert response["error"] == "Something went wrong"
    end

    test "sets trial expiration date to 14 days from now", %{
      conn: conn,
      trial_org_1: trial_org_1,
      valid_otp: valid_otp
    } do
      params = %{
        "phone" => @valid_phone,
        "otp" => valid_otp,
        "name" => "Test User",
        "password" => @password
      }

      before_allocation = DateTime.utc_now() |> DateTime.truncate(:second)

      conn =
        conn
        |> put_req_header("x-api-key", @valid_token)

      TrialAccountController.trial(conn, params)

      updated_org = Repo.get!(Organization, trial_org_1.id, skip_organization_id: true)

      assert updated_org.trial_expiration_date != nil

      expected_date = DateTime.add(before_allocation, 14, :day)

      diff = DateTime.diff(updated_org.trial_expiration_date, expected_date)
      assert abs(diff) <= 2
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

    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert!()
  end
end
