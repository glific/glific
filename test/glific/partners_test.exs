defmodule Glific.PartnersTest do
  alias Faker.{Name, Phone}
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
      provider = provider_fixture()
      assert Partners.list_providers() == [provider]
    end

    test "list_providers/1 with multiple provider filteres" do
      _provider1 = provider_fixture(@valid_attrs)
      provider1 = provider_fixture(@valid_attrs_1)

      provider_list = Partners.list_providers(%{filter: %{name: provider1.name}})
      assert provider_list == [provider1]

      provider_list = Partners.list_providers(%{filter: %{url: provider1.url}})
      assert provider_list == [provider1]

      provider_list = Partners.list_providers()
      assert length(provider_list) == 2
    end

    test "count_providers/0 returns count of all providers" do
      provider_fixture()
      assert Partners.count_providers() == 1

      provider_fixture(@valid_attrs_1)
      assert Partners.count_providers() == 2

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

      assert length(Partners.list_providers()) == 4
    end

    test "ensure that creating providers with same name give an error" do
      provider_fixture(@valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Partners.create_provider(@valid_attrs)
    end
  end

  describe "organizations" do
    alias Glific.Partners.Organization

    @valid_org_attrs %{
      name: "Organization Name",
      display_name: "Organization Display Name",
      contact_name: "Organization Contact person",
      email: "Contact person email",
      provider_key: "Provider key",
      provider_number: "991737373"
    }

    @valid_org_attrs_1 %{
      name: "Organization Name 1",
      display_name: "Organization Display Name 1",
      contact_name: "Organization Contact person 1",
      email: "Contact person email 1",
      provider_key: "Provider key 1",
      provider_number: "9917373731"
    }

    @update_org_attrs %{
      name: "Updated Name",
      display_name: "Updated Display Name 1",
      contact_name: "Updated Contact"
    }

    @invalid_org_attrs %{provider_id: nil, name: nil, contact_name: nil}

    @spec contact_fixture() :: Contacts.Contact.t()
    def contact_fixture do
      {:ok, contact} =
        Glific.Contacts.create_contact(%{
          name: Name.name(),
          phone: Phone.EnUs.phone()
        })

      contact
    end

    def organization_fixture(attrs \\ %{}) do
      provider = provider_fixture(%{name: Faker.Name.name()})
      contact = contact_fixture()

      {:ok, organization} =
        attrs
        |> Enum.into(@valid_org_attrs)
        |> Map.merge(%{provider_id: provider.id, contact_id: contact.id})
        |> Partners.create_organization()

      organization
    end

    test "list_organizations/0 returns all organizations" do
      organization = organization_fixture()
      assert Partners.list_organizations() == [organization]
    end

    test "count_organizations/0 returns count of all organizations" do
      organization_fixture()
      assert Partners.count_organizations() == 1

      organization_fixture(@valid_org_attrs_1)
      assert Partners.count_organizations() == 2

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
               |> Map.merge(%{contact_id: contact_fixture().id})
               |> Partners.create_organization()

      assert organization.name == @valid_org_attrs.name
      assert organization.display_name == @valid_org_attrs.display_name
      assert organization.email == @valid_org_attrs.email
      assert organization.provider_number == @valid_org_attrs.provider_number
    end

    test "create_organization/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Partners.create_organization(@invalid_org_attrs)
    end

    test "update_organization/2 with valid data updates the organization" do
      organization = organization_fixture()

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, @update_org_attrs)

      assert organization.name == @update_org_attrs.name
      assert organization.contact_name == @update_org_attrs.contact_name
    end

    test "update_organization/2 with invalid data returns error changeset" do
      organization = organization_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Partners.update_organization(organization, @invalid_org_attrs)

      assert organization == Partners.get_organization!(organization.id)
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

      assert length(Partners.list_organizations()) == 2
    end

    test "list_organization/1 with multiple organization filteres" do
      _org0 = organization_fixture(@valid_org_attrs)
      org1 = organization_fixture(@valid_org_attrs_1)

      org_list = Partners.list_organizations(%{filter: %{name: org1.name}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{filter: %{display_name: org1.display_name}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{filter: %{contact_name: org1.contact_name}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{filter: %{email: org1.email}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{filter: %{provider_number: org1.provider_number}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{order: :asc, filter: %{name: "ABC"}})
      assert org_list == []

      org_list = Partners.list_organizations()
      assert length(org_list) == 2
    end

    test "list_organizations/1 with foreign key filters" do
      provider = provider_fixture(@valid_attrs)

      {:ok, organization} =
        @valid_org_attrs
        |> Map.merge(%{provider_id: provider.id})
        |> Partners.create_organization()

      assert [organization] == Partners.list_organizations(%{filter: %{provider: provider.name}})

      assert [] == Partners.list_organizations(%{filter: %{provider: "RandomString"}})
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
  end
end
