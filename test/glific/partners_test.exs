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
  end
end
