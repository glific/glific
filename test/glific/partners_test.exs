defmodule Glific.PartnersTest do
  alias Faker.{Person, Phone}
  use Glific.DataCase, async: true
  alias Glific.Partners

  describe "provider" do
    alias Glific.Partners.Provider

    @valid_attrs %{
      name: "some name",
      url: "some url",
      api_end_point: "some api_end_point"
    }
    @valid_attrs_1 %{
      name: "some name 1",
      url: "some url 1",
      api_end_point: "some api_end_point 1"
    }
    @valid_attrs_2 %{
      name: "some name 2",
      url: "some url 2",
      api_end_point: "some api_end_point 2"
    }
    @valid_attrs_3 %{
      name: "some name 3",
      url: "some url 3",
      api_end_point: "some api_end_point 3"
    }
    @update_attrs %{
      name: "some updated name",
      url: "some updated url",
      api_end_point: "some updated api_end_point"
    }
    @invalid_attrs %{
      name: nil,
      url: nil,
      api_end_point: nil
    }

    def provider_fixture(attrs \\ %{}) do
      {:ok, provider} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Partners.create_provider()

      provider
    end

    test "list_providers/0 returns all providers" do
      _provider = provider_fixture()
      assert length(Partners.list_providers()) >= 1
    end

    test "list_providers/1 with multiple provider filteres" do
      _provider1 = provider_fixture(@valid_attrs)
      provider1 = provider_fixture(@valid_attrs_1)

      provider_list = Partners.list_providers(%{filter: %{name: provider1.name}})
      assert provider_list == [provider1]

      provider_list = Partners.list_providers(%{filter: %{url: provider1.url}})
      assert provider_list == [provider1]

      provider_list = Partners.list_providers()
      assert length(provider_list) >= 2
    end

    test "count_providers/0 returns count of all providers" do
      provider_fixture()
      assert Partners.count_providers() >= 1

      provider_fixture(@valid_attrs_1)
      assert Partners.count_providers() >= 2

      assert Partners.count_providers(%{filter: %{name: "some name 1"}}) == 1
    end

    test "get_provider!/1 returns the provider with given id" do
      provider = provider_fixture()
      assert Partners.get_provider!(provider.id) == provider
    end

    test "create_provider/1 with valid data creates a provider" do
      assert {:ok, %Provider{} = provider} = Partners.create_provider(@valid_attrs)
      assert provider.api_end_point == "some api_end_point"
      assert provider.name == "some name"
      assert provider.url == "some url"
    end

    test "create_provider/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Partners.create_provider(@invalid_attrs)
    end

    test "update_provider/2 with valid data updates the provider" do
      provider = provider_fixture()
      assert {:ok, %Provider{} = provider} = Partners.update_provider(provider, @update_attrs)
      assert provider.api_end_point == "some updated api_end_point"
      assert provider.name == "some updated name"
      assert provider.url == "some updated url"
    end

    test "update_provider/2 with invalid data returns error changeset" do
      provider = provider_fixture()
      assert {:error, %Ecto.Changeset{}} = Partners.update_provider(provider, @invalid_attrs)
      assert provider == Partners.get_provider!(provider.id)
    end

    test "delete_provider/1 deletes the provider" do
      provider = provider_fixture()
      assert {:ok, %Provider{}} = Partners.delete_provider(provider)
      assert_raise Ecto.NoResultsError, fn -> Partners.get_provider!(provider.id) end
    end

    test "ensure that delete_provider/1 with foreign key constraints give error" do
      organization = organization_fixture()
      provider = Partners.get_provider!(organization.provider_id)
      assert {:error, _} = Partners.delete_provider(provider)
    end

    test "change_provider/1 returns a provider changeset" do
      provider = provider_fixture()
      assert %Ecto.Changeset{} = Partners.change_provider(provider)
    end

    test "list_providers/1 with multiple providers" do
      _c0 = provider_fixture(@valid_attrs)
      _c1 = provider_fixture(@valid_attrs_1)
      _c2 = provider_fixture(@valid_attrs_2)
      _c3 = provider_fixture(@valid_attrs_3)

      assert length(Partners.list_providers()) >= 4
    end

    test "ensure that creating providers with same name give an error" do
      provider_fixture(@valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Partners.create_provider(@valid_attrs)
    end
  end

  describe "organizations" do
    alias Glific.{
      Caches,
      Partners.Organization,
      Settings
    }

    @valid_org_attrs %{
      name: "Organization Name",
      shortcode: "organization_shortcode",
      email: "Contact person email",
      provider_key: "Provider key",
      provider_phone: "991737373"
    }

    @valid_org_attrs_1 %{
      name: "Organization Name 1",
      shortcode: "organization_shortcode 1",
      email: "Contact person email 1",
      provider_key: "Provider key 1",
      provider_phone: "9917373731"
    }

    @update_org_attrs %{
      name: "Updated Name",
      shortcode: "updated_shortcode"
    }

    @invalid_org_attrs %{provider_id: nil, name: nil}

    @valid_default_language_attrs %{
      label: "English (United States)",
      label_locale: "English",
      locale: "en_US",
      is_active: true
    }

    def default_language_fixture(attrs \\ %{}) do
      {:ok, default_language} =
        attrs
        |> Enum.into(@valid_default_language_attrs)
        |> Settings.language_upsert()

      default_language
    end

    @spec contact_fixture() :: Contacts.Contact.t()
    def contact_fixture do
      {:ok, contact} =
        Glific.Contacts.create_contact(%{
          name: Person.name(),
          phone: Phone.EnUs.phone()
        })

      contact
    end

    def organization_fixture(attrs \\ %{}) do
      default_language = default_language_fixture(attrs)
      provider = provider_fixture(%{name: Person.name()})

      {:ok, organization} =
        attrs
        |> Enum.into(@valid_org_attrs)
        |> Map.merge(%{provider_id: provider.id, default_language_id: default_language.id})
        |> Partners.create_organization()

      organization
    end

    test "list_organizations/0 returns all organizations" do
      _organization = organization_fixture()
      assert length(Partners.list_organizations()) >= 1
    end

    test "count_organizations/0 returns count of all organizations" do
      organization_fixture()
      assert Partners.count_organizations() >= 1

      organization_fixture(@valid_org_attrs_1)
      assert Partners.count_organizations() >= 2

      assert Partners.count_organizations(%{filter: %{name: "Organization Name 1"}}) == 1
    end

    test "get_organization!/1 returns the organization with given id" do
      organization = organization_fixture()
      assert Partners.get_organization!(organization.id) == organization
    end

    test "create_organization/1 with valid data creates an organization" do
      assert {:ok, %Organization{} = organization} =
               @valid_org_attrs
               |> Map.merge(%{provider_id: provider_fixture().id})
               |> Map.merge(%{default_language_id: default_language_fixture().id})
               |> Partners.create_organization()

      assert organization.name == @valid_org_attrs.name
      assert organization.shortcode == @valid_org_attrs.shortcode
      assert organization.email == @valid_org_attrs.email
      assert organization.provider_phone == @valid_org_attrs.provider_phone
    end

    test "create_organization/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Partners.create_organization(@invalid_org_attrs)
    end

    test "create_organization/1 should add default values for organization settings" do
      {:ok, %Organization{} = organization} =
        @valid_org_attrs
        |> Map.merge(%{provider_id: provider_fixture().id})
        |> Map.merge(%{default_language_id: default_language_fixture().id})
        |> Partners.create_organization()

      assert organization.out_of_office.enabled == false
      day1 = get_in(organization.out_of_office.enabled_days, [Access.at(0)])
      assert day1.enabled == false
    end

    test "update_organization/2 with valid data updates the organization" do
      organization = organization_fixture()

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, @update_org_attrs)

      assert organization.name == @update_org_attrs.name
    end

    test "update_organization/2 with invalid data returns error changeset" do
      organization = organization_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Partners.update_organization(organization, @invalid_org_attrs)

      assert organization == Partners.get_organization!(organization.id)
    end

    test "update_organization/2 with oraganization settings" do
      organization = organization_fixture()

      update_org_attrs =
        @update_org_attrs
        |> Map.merge(%{
          out_of_office: %{
            enabled: true,
            start_time: ~T[10:00:00],
            end_time: ~T[20:00:00],
            enabled_days: [
              %{
                id: 1,
                enabled: true
              }
            ],
            flow_id: 1
          }
        })

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, update_org_attrs)

      assert organization.out_of_office.enabled == true
      assert organization.out_of_office.start_time == ~T[10:00:00]
      day1 = get_in(organization.out_of_office.enabled_days, [Access.at(0)])
      assert day1.enabled == true
      # Days in the input should be updated accordingly, other days should be disabled
      day2 = get_in(organization.out_of_office.enabled_days, [Access.at(1)])
      assert day2.enabled == false

      # disable out_of_office setting
      update_org_attrs =
        @update_org_attrs
        |> Map.merge(%{
          out_of_office: %{
            enabled: false
          }
        })

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, update_org_attrs)

      assert organization.out_of_office.enabled == false
    end

    test "delete_organization/1 deletes the organization" do
      organization = organization_fixture()
      assert {:ok, %Organization{}} = Partners.delete_organization(organization)
      assert_raise Ecto.NoResultsError, fn -> Partners.get_organization!(organization.id) end
    end

    test "change_organization/1 returns a organization changeset" do
      organization = organization_fixture()
      assert %Ecto.Changeset{} = Partners.change_organization(organization)
    end

    test "list_contacts/1 with multiple contacts" do
      _org0 = organization_fixture(@valid_org_attrs)
      _org1 = organization_fixture(@valid_org_attrs_1)

      assert length(Partners.list_organizations()) >= 2
    end

    test "list_organization/1 with multiple organization filteres" do
      _org0 = organization_fixture(@valid_org_attrs)
      org1 = organization_fixture(@valid_org_attrs_1)

      org_list = Partners.list_organizations(%{filter: %{name: org1.name}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{filter: %{shortcode: org1.shortcode}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{filter: %{email: org1.email}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{filter: %{provider_phone: org1.provider_phone}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{order: :asc, filter: %{name: "ABC"}})
      assert org_list == []

      org_list = Partners.list_organizations()
      assert length(org_list) >= 3
    end

    test "list_organizations/1 with foreign key filters" do
      provider = provider_fixture(@valid_attrs)
      default_language = default_language_fixture()

      {:ok, organization} =
        @valid_org_attrs
        |> Map.merge(%{default_language_id: default_language.id})
        |> Map.merge(%{provider_id: provider.id})
        |> Partners.create_organization()

      assert [organization] == Partners.list_organizations(%{filter: %{provider: provider.name}})

      assert [organization] ==
               Partners.list_organizations(%{filter: %{name: "Organization Name"}})

      assert [] == Partners.list_organizations(%{filter: %{provider: "RandomString"}})

      assert [] == Partners.list_organizations(%{filter: %{default_language: "Hindi"}})
    end

    test "ensure that creating organization with out provider give an error" do
      assert {:error, %Ecto.Changeset{}} = Partners.create_organization(@valid_org_attrs)
    end

    test "ensure that creating organization  with same whats app number give an error" do
      organization = organization_fixture(@valid_org_attrs)

      assert {:error, %Ecto.Changeset{}} =
               Map.merge(@valid_org_attrs, %{provider_id: organization.provider_id})
               |> Partners.create_organization()
    end

    test "set_out_of_office_values/1 should set values for hours and days" do
      organization = organization_fixture()

      updated_organization = Partners.set_out_of_office_values(organization)
      assert updated_organization.hours == []
      assert updated_organization.days == []

      update_org_attrs =
        @update_org_attrs
        |> Map.merge(%{
          out_of_office: %{
            enabled: true,
            start_time: ~T[10:00:00],
            end_time: ~T[20:00:00],
            enabled_days: [
              %{id: 1, enabled: true},
              %{id: 2, enabled: true}
            ],
            flow_id: 1
          }
        })

      {:ok, updated_organization} = Partners.update_organization(organization, update_org_attrs)

      organization_with_set_values = Partners.set_out_of_office_values(updated_organization)
      assert organization_with_set_values.hours == [~T[10:00:00], ~T[20:00:00]]
      assert organization_with_set_values.days == [1, 2]
    end

    test "active_organizations/0 should return list of active organizations" do
      organization = organization_fixture()
      organizations = Partners.active_organizations()
      assert organizations[organization.id] != nil

      {:ok, _} = Partners.update_organization(organization, %{is_active: false})
      organizations = Partners.active_organizations()
      assert organizations[organization.id] == nil
    end

    test "organization/1 should return cached data" do
      assert {:ok, false} = Caches.get("organization")

      organization = organization_fixture()
      Partners.organization(organization.id)

      assert {:ok, organization} = Caches.get("organization")
      assert organization.hours != nil
      assert organization.days != nil
    end
  end
end
