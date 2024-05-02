defmodule Glific.OnboardTest do
  alias Glific.Registrations.Registration
  use Glific.DataCase
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
    "shortcode" => "short",
    "gstin" => "abcabcabcabcabc",
    "registered_address" => "registered_address",
    "current_address" => "current_address",
    "registration_doc_link" => "https://storage.googleapis.com/1/file.doc"
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_billing(organization)
    ExVCR.Config.cassette_library_dir("test/support/ex_vcr")

    Tesla.Mock.mock_global(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "ok",
              "users" => [1, 2, 3]
            })
        }

      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "token" => "ks_test_token",
              "status" => "success",
              "templates" => [],
              "template" => %{"id" => Ecto.UUID.generate(), "status" => "PENDING"}
            })
        }
    end)

    :ok
  end

  test "ensure that validations are applied on params while creating an org" do
    # lets remove a couple and mess up the others to get most of the errors
    registered_address = String.duplicate("lorum epsum", 300)

    attrs =
      @valid_attrs
      |> Map.delete("app_name")
      |> Map.put("email", "foobar")
      |> Map.put("phone", "93'#$%^")
      |> Map.put("shortcode", "glific")
      |> Map.put("gstin", "abcabcabcabcabc")
      |> Map.put("registered_address", registered_address)
      |> Map.delete("current_address")
      |> Map.put("registration_doc_link", "https://fa.com")

    %{
      messages: %{
        phone: "Phone is not valid.",
        shortcode: "Shortcode has already been taken.",
        registered_address: "registered_address cannot be more than 300 letters.",
        current_address: "current_address cannot be empty.",
        api_key_name: "API Key or App Name is empty."
      },
      is_valid: false
    } = Onboard.setup(attrs)
  end

  @tag :sett
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
    assert result.registration_id != nil
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

  @tag :upreg
  test "update_registration, without registration_id" do
    assert %{messages: %{registration_id: "Registration ID is empty."}, is_valid: false} =
             Onboard.update_registration(%{})
  end

  @tag :upreg
  test "update_registration, invalid registration_id" do
    assert %{
             messages: %{registration_id: "Registration doesn't exist for given registration ID."},
             is_valid: false
           } =
             Onboard.update_registration(%{"registration_id" => 0})
  end

  @tag :upregg
  test "update_registration, valid registration_id" do
    attrs =
      @valid_attrs
      |> Map.put("shortcode", "new_glific")
      |> Map.put("phone", "919917443995")

    result = Onboard.setup(attrs)

    # Registration
    # |> where([reg], reg.organization_id == ^result.organization.id)
    # |> Repo.all()
    # |> IO.inspect(label: "regs")

    Repo.all(Registration) |> IO.inspect()
    # Ecto.Adapters.SQL.query(Repo, "select * from registrations") |> IO.inspect()
    assert %{
             messages: %{registration_id: "Registration doesn't exist for given registration ID."},
             is_valid: false
           } =
             Onboard.update_registration(%{"registration_id" => result.registration_id})
  end
end
