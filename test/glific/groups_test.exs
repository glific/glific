defmodule Glific.GroupsTest do
  use Glific.DataCase

  alias Glific.{Groups, Groups.Group}

  describe "groups" do
    @valid_attrs %{
      label: "some group",
      is_restricted: false
    }
    @valid_other_attrs %{
      label: "other group",
      is_restricted: true
    }
    @update_attrs %{
      label: "updated group",
      is_restricted: false
    }
    @invalid_attrs %{
      label: nil
    }

    def group_fixture(attrs \\ %{}) do
      {:ok, group} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Groups.create_group()

      group
    end

    test "list_groups/0 returns all groups" do
      group = group_fixture()
      assert Groups.list_groups() == [group]
    end

    test "count_groups/0 returns count of all groups" do
      _ = group_fixture()
      assert Groups.count_groups() == 1

      _ = group_fixture(@valid_other_attrs)
      assert Groups.count_groups() == 2

      assert Groups.count_groups(%{filter: %{label: "other group"}}) == 1
    end

    test "get_group!/1 returns the group with given id" do
      group = group_fixture()
      assert Groups.get_group!(group.id) == group
    end

    test "create_group/1 with valid data creates a group" do
      assert {:ok, %Group{} = group} = Groups.create_group(@valid_attrs)
      assert group.is_restricted == false
      assert group.label == "some group"
    end

    test "create_group/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Groups.create_group(@invalid_attrs)
    end

    test "update_group/2 with valid data updates the group" do
      group = group_fixture()
      assert {:ok, %Group{} = group} = Groups.update_group(group, @update_attrs)
      assert group.label == "updated group"
      assert group.is_restricted == false
    end

    test "update_group/2 with invalid data returns error changeset" do
      group = group_fixture()
      assert {:error, %Ecto.Changeset{}} = Groups.update_group(group, @invalid_attrs)
      assert group == Groups.get_group!(group.id)
    end

    test "delete_group/1 deletes the group" do
      group = group_fixture()
      assert {:ok, %Group{}} = Groups.delete_group(group)
      assert_raise Ecto.NoResultsError, fn -> Groups.get_group!(group.id) end
    end

    test "change_group/1 returns a group changeset" do
      group = group_fixture()
      assert %Ecto.Changeset{} = Groups.change_group(group)
    end

    test "list_groups/1 with multiple items" do
      group1 = group_fixture()
      group2 = group_fixture(@valid_other_attrs)
      groups = Groups.list_groups()
      assert length(groups) == 2
      [h, t | _] = groups
      assert (h == group1 && t == group2) || (h == group2 && t == group1)
    end

    test "list_groups/1 with multiple items sorted" do
      group1 = group_fixture()
      group2 = group_fixture(@valid_other_attrs)
      groups = Groups.list_groups(%{opts: %{order: :asc}})
      assert length(groups) == 2
      [h, t | _] = groups
      assert h == group2 && t == group1
    end

    test "list_groups/1 with items filtered" do
      _group1 = group_fixture()
      group2 = group_fixture(@valid_other_attrs)
      groups = Groups.list_groups(%{opts: %{order: :asc}, filter: %{label: "other group"}})
      assert length(groups) == 1
      [h] = groups
      assert h == group2
    end

  end
end
