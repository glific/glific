defmodule Glific.PartnersTest do
  use Glific.DataCase

  alias Glific.Partners

  describe "partners" do
    alias Glific.Partners.BSP

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

    def bsp_fixture(attrs \\ %{}) do
      {:ok, bsp} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Partners.create_bsp()

      bsp
    end

    test "list_bsps/0 returns all bsps" do
      bsp = bsp_fixture()
      assert Partners.list_bsps() == [bsp]
    end

    test "get_bsp!/1 returns the bsp with given id" do
      bsp = bsp_fixture()
      assert Partners.get_bsp!(bsp.id) == bsp
    end

    test "create_bsp/1 with valid data creates a bsp" do
      assert {:ok, %BSP{} = bsp} = Partners.create_bsp(@valid_attrs)
      assert bsp.api_end_point == "some api_end_point"
      assert bsp.name == "some name"
      assert bsp.url == "some url"
    end

    test "create_bsp/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Partners.create_bsp(@invalid_attrs)
    end

    test "update_bsp/2 with valid data updates the bsp" do
      bsp = bsp_fixture()
      assert {:ok, %BSP{} = bsp} = Partners.update_bsp(bsp, @update_attrs)
      assert bsp.api_end_point == "some updated api_end_point"
      assert bsp.name == "some updated name"
      assert bsp.url == "some updated url"
    end

    test "update_bsp/2 with invalid data returns error changeset" do
      bsp = bsp_fixture()
      assert {:error, %Ecto.Changeset{}} = Partners.update_bsp(bsp, @invalid_attrs)
      assert bsp == Partners.get_bsp!(bsp.id)
    end

    test "delete_bsp/1 deletes the bsp" do
      bsp = bsp_fixture()
      assert {:ok, %BSP{}} = Partners.delete_bsp(bsp)
      assert_raise Ecto.NoResultsError, fn -> Partners.get_bsp!(bsp.id) end
    end

    test "change_bsp/1 returns a bsp changeset" do
      bsp = bsp_fixture()
      assert %Ecto.Changeset{} = Partners.change_bsp(bsp)
    end

    test "list_bsps/1 with multiple bsps" do
      _c0 = bsp_fixture(@valid_attrs)
      _c1 = bsp_fixture(@valid_attrs_1)
      _c2 = bsp_fixture(@valid_attrs_2)
      _c3 = bsp_fixture(@valid_attrs_3)

      assert length(Partners.list_bsps()) == 4
    end

    test "ensure that creating bsps with same name give an error" do
      bsp_fixture(@valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Partners.create_bsp(@valid_attrs)
    end

    alias Glific.Partners.Organization

    @valid_org_attrs %{
      name: "Organization Name",
      contact_name: "Organization Contact person",
      email: "Contact person email",
      bsp_key: "BSP key",
      wa_number: "991737373"
    }

    @valid_org_attrs_1 %{
      name: "Organization Name 1",
      contact_name: "Organization Contact person 1",
      email: "Contact person email 1",
      bsp_key: "BSP key 1",
      wa_number: "9917373731"
    }

    @update_org_attrs %{
      name: "Updated Name",
      contact_name: "Updated Contact"
    }
    @invalid_org_attrs %{bsp_id: nil, name: nil, contact_name: nil}

    def organization_fixture(attrs \\ %{}) do
      bsp = bsp_fixture(%{name: Faker.Name.name()})

      {:ok, organization} =
        attrs
        |> Enum.into(@valid_org_attrs)
        |> Map.merge(%{bsp_id: bsp.id})
        |> Partners.create_organization()

      organization
    end

    test "list_organizations/0 returns all organizations" do
      organization = organization_fixture()
      assert Partners.list_organizations() == [organization]
    end

    test "get_organization!/1 returns the organization with given id" do
      organization = organization_fixture()
      assert Partners.get_organization!(organization.id) == organization
    end

    test "create_organization/1 with valid data creates an organization" do
      assert {:ok, %Organization{} = organization} =
               @valid_org_attrs
               |> Map.merge(%{bsp_id: bsp_fixture().id})
               |> Partners.create_organization()

      assert organization.name == @valid_org_attrs.name
      assert organization.email == @valid_org_attrs.email
      assert organization.wa_number == @valid_org_attrs.wa_number
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

      org_list = Partners.list_organizations(%{filter: %{contact_name: org1.contact_name}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{filter: %{email: org1.email}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{filter: %{bsp_key: org1.bsp_key}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{filter: %{wa_number: org1.wa_number}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{order: :asc, filter: %{name: "ABC"}})
      assert org_list == []

      org_list = Partners.list_organizations()
      assert length(org_list) == 2
    end

    test "ensure that creating organization with out bsp give an error" do
      assert {:error, %Ecto.Changeset{}} = Partners.create_organization(@valid_org_attrs)
    end

    test "ensure that creating organization  with same whats app number give an error" do
      organization = organization_fixture(@valid_org_attrs)

      assert {:error, %Ecto.Changeset{}} =
               Map.merge(@valid_org_attrs, %{bsp_id: organization.bsp_id})
               |> Partners.create_organization()
    end
  end
end
