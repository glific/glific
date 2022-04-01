defmodule Glific.OnboardTest do
  use Glific.DataCase
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

  alias Glific.{
    Fixtures,
    Partners.Organization,
    Saas.Onboard,
    Seeds.SeedsDev
  }

  @valid_attrs %{
    "name" => "First Organization",
    "phone" => "+911234567890",
    "api_key" => "fake api key",
    "app_name" => "fake app name",
    "email" => "lobo@yahoo.com",
    "shortcode" => "short"
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_billing(organization)
    HTTPoison.start()
    ExVCR.Config.cassette_library_dir("test/support/ex_vcr")

    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "ok",
              "users" => [1, 2, 3]
            })
        }
    end)

    :ok
  end

  test "ensure that sending in valid parameters, creates an organization, contact and credential" do
    result = Onboard.setup(@valid_attrs)

    assert result.is_valid == true
    assert result.organization != nil
    assert result.contact != nil
    assert result.credential != nil

    # lets remove a couple and mess up the others to get most of the errors
    attrs =
      @valid_attrs
      |> Map.delete("app_name")
      |> Map.put("email", "foobar")
      |> Map.put("phone", "93'#$%^")
      |> Map.put("shortcode", "glific")

    result = Onboard.setup(attrs)

    assert result.is_valid == false
    assert result.messages != []
  end

  test "ensure that sending in valid parameters, update organization status" do
    result = Onboard.setup(@valid_attrs)
    {:ok, organization} = Repo.fetch_by(Organization, %{name: result.organization.name})

    updated_organization = Onboard.status(organization.id, :active)

    assert updated_organization.is_active == true

    # should update is_approved
    updated_organization = Onboard.status(organization.id, :approved)
    assert updated_organization.is_approved == true
  end

  test "ensure that sending in valid parameters, update organization status as is_active false and change subscription plan",
       attrs do
    use_cassette "update_subscription_inactive_plan" do
      {:ok, organization} = Repo.fetch_by(Organization, %{organization_id: attrs.organization_id})

      updated_organization = Onboard.status(organization.id, :suspended)

      assert updated_organization.is_active == false
    end
  end

  test "ensure that sending in valid parameters, update organization status as is_active false for organization without billing" do
    organization = Fixtures.organization_fixture()
    {:ok, organization} = Repo.fetch_by(Organization, %{organization_id: organization.id})

    updated_organization = Onboard.status(organization.id, :inactive)

    assert updated_organization.is_active == false
  end

  test "ensure that sending in valid parameters, delete inactive organization" do
    result = Onboard.setup(@valid_attrs)

    {:ok, organization} = Repo.fetch_by(Organization, %{name: result.organization.name})
    Onboard.delete(organization.id, true)

    assert {:error, ["Elixir.Glific.Partners.Organization", "Resource not found"]} ==
             Repo.fetch_by(Organization, %{name: result.organization.name})
  end
end
