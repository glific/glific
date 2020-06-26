defmodule Glific.GroupsTest do
  use Glific.DataCase

  alias Glific.{Groups, Groups.Group}

  alias Glific.{Groups.ContactGroup, Groups.UserGroup}

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

  describe "contacts_groups" do
    setup do
      lang = Glific.Seeds.seed_language()
      default_provider = Glific.Seeds.seed_providers()
      Glific.Seeds.seed_organizations(default_provider, lang)
      Glific.Seeds.seed_contacts()
      :ok
    end

    def contact_group_fixture() do
      [contact | _] = Glific.Contacts.list_contacts()
      valid_attrs = %{
        contact_id: contact.id,
        group_id: group_fixture().id
      }

      {:ok, contact_group} =
        valid_attrs
        |> Groups.create_contact_group()

      contact_group
    end

    test "create_contacts_group/1 with valid data creates a group" do
      [contact | _] = Glific.Contacts.list_contacts()
      group = group_fixture()
      {:ok, contact_group} = Groups.create_contact_group(%{contact_id: contact.id, group_id: group.id})
      assert contact_group.contact_id == contact.id
      assert contact_group.group_id == group.id
    end

    test "delete_contacts_group/1 deletes the group" do
      contact_group = contact_group_fixture()
      assert {:ok, %ContactGroup{}} = Groups.delete_contact_group(contact_group)
    end

    test "ensure that creating contact_group with same contact and group give an error" do
      [contact | _] = Glific.Contacts.list_contacts()
      group = group_fixture()
      Groups.create_contact_group(%{contact_id: contact.id, group_id: group.id})

      assert {:error, %Ecto.Changeset{}} =
               Groups.create_contact_group(%{contact_id: contact.id, group_id: group.id})
    end
  end

  describe "users_groups" do
    setup do
      Glific.Seeds.seed_users()
      :ok
    end

    def user_group_fixture() do
      [user | _] = Glific.Users.list_users()
      valid_attrs = %{
        user_id: user.id,
        group_id: group_fixture().id
      }

      {:ok, user_group} =
        valid_attrs
        |> Groups.create_user_group()

      user_group
    end

    test "create_users_group/1 with valid data creates a group" do
      [user | _] = Glific.Users.list_users()
      group = group_fixture()
      {:ok, user_group} = Groups.create_user_group(%{user_id: user.id, group_id: group.id})
      assert user_group.user_id == user.id
      assert user_group.group_id == group.id
    end

    test "delete_users_group/1 deletes the group" do
      user_group = user_group_fixture()
      assert {:ok, %UserGroup{}} = Groups.delete_user_group(user_group)
    end

    test "ensure that creating user_group with same user and group give an error" do
      [user | _] = Glific.Users.list_users()
      group = group_fixture()
      Groups.create_user_group(%{user_id: user.id, group_id: group.id})

      assert {:error, %Ecto.Changeset{}} =
               Groups.create_user_group(%{user_id: user.id, group_id: group.id})
    end
  end
end
