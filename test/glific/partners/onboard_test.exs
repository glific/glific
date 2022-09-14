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

  @partner_url "https://partner.gupshup.io/partner/account"

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

      %{method: :post, url: url} ->
        cond do
          String.contains?(url, @partner_url <> "/login") ->
            %Tesla.Env{
              status: 200,
              body:
                Jason.encode!(%{
                  "token" => "ks_test_token"
                })
            }

          true ->
            %Tesla.Env{
              status: 200,
              body:
                Jason.encode!(%{
                  "status" => "success",
                  "templates" => [],
                  "template" => %{"id" => Ecto.UUID.generate(), "status" => "PENDING"}
                })
            }
        end
    end)

    :ok
  end

  test "ensure that validations are applied on params while creating an org" do
    # lets remove a couple and mess up the others to get most of the errors
    attrs =
      @valid_attrs
      |> Map.delete("app_name")
      |> Map.put("email", "foobar")
      |> Map.put("phone", "93'#$%^")
      |> Map.put("shortcode", "glific")

    result = Onboard.setup(attrs)

    assert result.is_valid == false
    assert result.messages != %{}
  end

  test "ensure that sending in valid parameters, creates an organization, contact and credential" do
    attrs =
      @valid_attrs
      |> Map.put("shortcode", "new_glific")
      |> Map.put("phone", "919917443995")

    result = Onboard.setup(attrs)

    assert result.is_valid == true
    assert result.messages == %{}
    assert result.organization != nil
    assert result.contact != nil
    assert result.credential != nil

    ## new org will have a common otp template
    [common_otp_template | _tail] =
      Glific.Templates.list_session_templates(%{
        is_hsm: true,
        organization_id: result.organization.id,
        shortocode: "common_otp"
      })

    assert common_otp_template.label == "common_otp"
    assert common_otp_template.organization_id == result.organization.id
  end

  test "ensure that sending in valid parameters, update organization status" do
    result = Onboard.setup(@valid_attrs)

    {:ok, organization} =
      Repo.fetch_by(Organization, %{name: result.organization.name}, skip_organization_id: true)

    updated_organization = Onboard.status(organization.id, :active)

    assert updated_organization.is_active == true

    # should update is_approved
    updated_organization = Onboard.status(organization.id, :approved)
    assert updated_organization.is_approved == true
  end

  test "ensure that sending in valid parameters, update organization status as is_active false and change subscription plan",
       attrs do
    use_cassette "update_subscription_inactive_plan" do
      {:ok, organization} =
        Repo.fetch_by(Organization, %{organization_id: attrs.organization_id},
          skip_organization_id: true
        )

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

    {:ok, organization} =
      Repo.fetch_by(Organization, %{name: result.organization.name}, skip_organization_id: true)

    Onboard.delete(organization.id, true)

    assert {:error, ["Elixir.Glific.Partners.Organization", "Resource not found"]} ==
             Repo.fetch_by(Organization, %{name: result.organization.name})
  end
end
