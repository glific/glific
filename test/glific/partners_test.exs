defmodule Glific.PartnersTest do
  use Glific.DataCase

  alias Glific.Partners

  describe "bsps" do
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
  end
end
