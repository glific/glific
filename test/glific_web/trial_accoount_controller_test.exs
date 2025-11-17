defmodule GlificWeb.API.V1.TrialAccountControllerTest do
  use GlificWeb.ConnCase

  alias Glific.{
    Partners.Organization,
    Repo,
    Seeds.SeedsDev
  }

  alias GlificWeb.API.V1.TrialAccountController

  @valid_token "test-trial-token-12345"

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()

    # Mock the token
    Application.put_env(:glific, GlificWeb.API.V1.TrialAccountController,
      trial_account_token: @valid_token
    )

    on_exit(fn ->
      Application.delete_env(:glific, GlificWeb.API.V1.TrialAccountController)
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

      %{
        trial_org_1: trial_org_1,
        trial_org_2: trial_org_2,
        allocated_org: allocated_org
      }
    end

    test "successfully allocates a trial account with valid token", %{
      conn: conn,
      trial_org_1: trial_org_1
    } do
      conn =
        conn
        |> put_req_header("x-api-key", @valid_token)

      conn = TrialAccountController.trial(conn, %{})

      response = json_response(conn, 200)
      assert response["success"] == true
      assert response["data"]["login_url"] == "https://#{trial_org_1.shortcode}.glific.com"
      assert response["data"]["expires_at"] != nil

      updated_org = Repo.get!(Organization, trial_org_1.id, skip_organization_id: true)
      assert updated_org.trial_expiration_date != nil
    end

    test "returns error when no trial accounts are available", %{
      conn: conn,
      trial_org_1: trial_org_1,
      trial_org_2: trial_org_2
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

      conn =
        conn
        |> put_req_header("x-api-key", @valid_token)

      conn = TrialAccountController.trial(conn, %{})

      assert json_response(conn, 503) == %{
               "success" => false,
               "error" => "No trial accounts available at the moment"
             }
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
