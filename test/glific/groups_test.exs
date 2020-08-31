defmodule Glific.GroupsTest do
  use Glific.DataCase

  alias Glific.{
    Contacts,
    Groups,
    Groups.ContactGroup,
    Groups.Group,
    Groups.UserGroup,
    Seeds.SeedsDev,
    Users
  }

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

    def group_fixture(attrs) do
      {:ok, group} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Groups.create_group()

      group
    end

    test "list_groups/1 returns all groups", attrs do
      group = group_fixture(attrs)
      assert Groups.list_groups(%{filter: attrs}) == [group]
    end

    test "count_groups/1 returns count of all groups", attrs do
      _ = group_fixture(attrs)
      assert Groups.count_groups(%{filter: attrs}) == 1

      _ = group_fixture(Map.merge(attrs, @valid_other_attrs))
      assert Groups.count_groups(%{filter: attrs}) == 2

      assert Groups.count_groups(%{filter: Map.merge(attrs, %{label: "other group"})}) == 1
    end

    test "get_group!/1 returns the group with given id", attrs do
      group = group_fixture(attrs)
      assert Groups.get_group!(group.id) == group
    end

    test "create_group/1 with valid data creates a group", attrs do
      assert {:ok, %Group{} = group} = Groups.create_group(Map.merge(attrs, @valid_attrs))
      assert group.is_restricted == false
      assert group.label == "some group"
    end

    test "create_group/1 with invalid data returns error changeset", attrs do
      assert {:error, %Ecto.Changeset{}} = Groups.create_group(Map.merge(attrs, @invalid_attrs))
    end

    test "update_group/2 with valid data updates the group", attrs do
      group = group_fixture(attrs)
      assert {:ok, %Group{} = group} = Groups.update_group(group, @update_attrs)
      assert group.label == "updated group"
      assert group.is_restricted == false
    end

    test "update_group/2 with invalid data returns error changeset", attrs do
      group = group_fixture(attrs)

      assert {:error, %Ecto.Changeset{}} =
               Groups.update_group(group, Map.merge(attrs, @invalid_attrs))

      assert group == Groups.get_group!(group.id)
    end

    test "delete_group/1 deletes the group", attrs do
      group = group_fixture(attrs)
      assert {:ok, %Group{}} = Groups.delete_group(group)
      assert_raise Ecto.NoResultsError, fn -> Groups.get_group!(group.id) end
    end

    test "change_group/1 returns a group changeset", attrs do
      group = group_fixture(attrs)
      assert %Ecto.Changeset{} = Groups.change_group(group)
    end

    test "list_groups/1 with multiple items", attrs do
      group1 = group_fixture(attrs)
      group2 = group_fixture(Map.merge(attrs, @valid_other_attrs))
      groups = Groups.list_groups(%{filter: attrs})
      assert length(groups) == 2
      [h, t | _] = groups
      assert (h == group1 && t == group2) || (h == group2 && t == group1)
    end

    test "list_groups/1 with multiple items sorted", attrs do
      group1 = group_fixture(attrs)
      group2 = group_fixture(Map.merge(attrs, @valid_other_attrs))
      groups = Groups.list_groups(%{opts: %{order: :asc}, filter: attrs})
      assert length(groups) == 2
      [h, t | _] = groups
      assert h == group2 && t == group1
    end

    test "list_groups/1 with items filtered", attrs do
      _group1 = group_fixture(attrs)
      group2 = group_fixture(Map.merge(attrs, @valid_other_attrs))

      groups =
        Groups.list_groups(%{
          opts: %{order: :asc},
          filter: Map.merge(attrs, %{label: "other group"})
        })

      assert length(groups) == 1
      [h] = groups
      assert h == group2
    end
  end

  describe "contacts_groups" do
    setup do
      default_provider = SeedsDev.seed_providers()
      SeedsDev.seed_organizations(default_provider)
      SeedsDev.seed_contacts()
      :ok
    end

    def contact_group_fixture(attrs) do
      [contact | _] = Contacts.list_contacts(%{filter: attrs})

      valid_attrs = %{
        contact_id: contact.id,
        group_id: group_fixture(attrs).id
      }

      {:ok, contact_group} =
        valid_attrs
        |> Groups.create_contact_group()

      contact_group
    end

    test "create_contacts_group/1 with valid data creates a group", attrs do
      [contact | _] = Contacts.list_contacts(%{filter: attrs})
      group = group_fixture(attrs)

      {:ok, contact_group} =
        Groups.create_contact_group(%{contact_id: contact.id, group_id: group.id})

      assert contact_group.contact_id == contact.id
      assert contact_group.group_id == group.id
    end

    test "delete_contacts_group/1 deletes the group", attrs do
      contact_group = contact_group_fixture(attrs)
      assert {:ok, %ContactGroup{}} = Groups.delete_contact_group(contact_group)
    end

    test "ensure that creating contact_group with same contact and group give an error", attrs do
      [contact | _] = Contacts.list_contacts(%{filter: attrs})
      group = group_fixture(attrs)
      Groups.create_contact_group(%{contact_id: contact.id, group_id: group.id})

      assert {:error, %Ecto.Changeset{}} =
               Groups.create_contact_group(%{contact_id: contact.id, group_id: group.id})
    end
  end

  describe "users_groups" do
    setup do
      SeedsDev.seed_users()
      :ok
    end

    def user_group_fixture(attrs) do
      [user | _] = Users.list_users(%{filter: attrs})

      valid_attrs = %{
        user_id: user.id,
        group_id: group_fixture(attrs).id
      }

      {:ok, user_group} =
        valid_attrs
        |> Groups.create_user_group()

      user_group
    end

    test "create_users_group/1 with valid data creates a group", attrs do
      [user | _] = Users.list_users(%{filter: attrs})
      group = group_fixture(attrs)
      {:ok, user_group} = Groups.create_user_group(%{user_id: user.id, group_id: group.id})
      assert user_group.user_id == user.id
      assert user_group.group_id == group.id
    end

    test "delete_users_group/1 deletes the group", attrs do
      user_group = user_group_fixture(attrs)
      assert {:ok, %UserGroup{}} = Groups.delete_user_group(user_group)
    end

    test "ensure that creating user_group with same user and group give an error", attrs do
      [user | _] = Users.list_users(%{filter: attrs})
      group = group_fixture(attrs)
      Groups.create_user_group(%{user_id: user.id, group_id: group.id})

      assert {:error, %Ecto.Changeset{}} =
               Groups.create_user_group(%{user_id: user.id, group_id: group.id})
    end

    test "update_user_groups/1 should add and delete user groups according to the input", attrs do
      [user | _] = Users.list_users(%{filter: attrs})
      group_1 = group_fixture(attrs)
      group_2 = group_fixture(Map.merge(attrs, %{label: "new group"}))
      group_3 = group_fixture(Map.merge(attrs, %{label: "another group"}))

      # add user groups
      :ok =
        Groups.update_user_groups(%{
          user_id: user.id,
          group_ids: ["#{group_1.id}", "#{group_2.id}"]
        })

      user_group_ids =
        Groups.UserGroup
        |> where([ug], ug.user_id == ^user.id)
        |> select([ug], ug.group_id)
        |> Repo.all()

      assert user_group_ids == [group_1.id, group_2.id]

      # update user groups
      :ok =
        Groups.update_user_groups(%{
          user_id: user.id,
          group_ids: ["#{group_1.id}", "#{group_3.id}"]
        })

      user_group_ids =
        Groups.UserGroup
        |> where([ug], ug.user_id == ^user.id)
        |> select([ug], ug.group_id)
        |> Repo.all()

      assert user_group_ids == [group_1.id, group_3.id]
    end
  end
end
