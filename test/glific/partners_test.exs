defmodule Glific.PartnersTest do
  use Glific.DataCase

  alias Glific.Partners

  describe "bsps" do
    alias Glific.Partners.BSP

    @valid_attrs %{api_end_point: "some api_end_point", name: "some name", url: "some url"}
    @update_attrs %{
      api_end_point: "some updated api_end_point",
      name: "some updated name",
      url: "some updated url"
    }
    @invalid_attrs %{api_end_point: nil, name: nil, url: nil}

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

    alias Glific.Partners.Organization

    @valid_organization_attrs %{
      name: "Organization Name",
      contact_name: "Organization Contact person",
      email: "Contact person email",
      bsp_key: "BSP key",
      wa_number: "991737373"
    }
    @update_organization_attrs %{
      name: "Updated Name",
      contact_name: "Updated Contact"
    }
    @invalid_organization_attrs %{bsp_id: nil, name: nil, contact_name: nil}

    def organization_fixture(attrs \\ %{}) do
      {:ok, organization} =
        attrs
        |> Enum.into(@valid_organization_attrs)
        |> Map.merge(%{bsp_id: bsp_fixture().id})
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
               @valid_organization_attrs
               |> Map.merge(%{bsp_id: bsp_fixture().id})
               |> Partners.create_organization()

      assert organization.name == @valid_organization_attrs.name
      assert organization.email == @valid_organization_attrs.email
      assert organization.wa_number == @valid_organization_attrs.wa_number
    end

    test "update_organization/2 with valid data updates the organization" do
      organization = organization_fixture()

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, @update_organization_attrs)

      assert organization.name == @update_organization_attrs.name
      assert organization.contact_name == @update_organization_attrs.contact_name
    end

    test "update_organization/2 with invalid data returns error changeset" do
      organization = organization_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Partners.update_organization(organization, @invalid_organization_attrs)

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
  end
end
