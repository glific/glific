defmodule Glific.AccessControlTest do
  use Glific.DataCase

  alias Glific.AccessControls

  describe "roles" do
    alias Glific.AccessControls.Role

    import Glific.AccessControlFixtures

    @invalid_attrs %{description: nil, is_reserved: nil, label: nil}

    test "list_roles/0 returns all roles" do
      role = role_fixture()
      assert AccessControls.list_roles() == [role]
    end

    test "get_role!/1 returns the role with given id" do
      role = role_fixture()
      assert AccessControls.get_role!(role.id) == role
    end

    test "create_role/1 with valid data creates a role" do
      valid_attrs = %{description: "some description", is_reserved: true, label: "some label"}

      assert {:ok, %Role{} = role} = AccessControls.create_role(valid_attrs)
      assert role.description == "some description"
      assert role.is_reserved == true
      assert role.label == "some label"
    end

    test "create_role/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = AccessControls.create_role(@invalid_attrs)
    end

    test "update_role/2 with valid data updates the role" do
      role = role_fixture()

      update_attrs = %{
        description: "some updated description",
        is_reserved: false,
        label: "some updated label"
      }

      assert {:ok, %Role{} = role} = AccessControls.update_role(role, update_attrs)
      assert role.description == "some updated description"
      assert role.is_reserved == false
      assert role.label == "some updated label"
    end

    test "update_role/2 with invalid data returns error changeset" do
      role = role_fixture()
      assert {:error, %Ecto.Changeset{}} = AccessControls.update_role(role, @invalid_attrs)
      assert role == AccessControls.get_role!(role.id)
    end

    test "delete_role/1 deletes the role" do
      role = role_fixture()
      assert {:ok, %Role{}} = AccessControls.delete_role(role)
      assert_raise Ecto.NoResultsError, fn -> AccessControls.get_role!(role.id) end
    end

    test "change_role/1 returns a role changeset" do
      role = role_fixture()
      assert %Ecto.Changeset{} = AccessControls.change_role(role)
    end
  end

  describe "permissions" do
    alias Glific.AccessControls.Permission

    import Glific.AccessControlFixtures

    @invalid_attrs %{entity: nil}

    test "list_permissions/0 returns all permissions" do
      permission = permission_fixture()
      assert AccessControls.list_permissions() == [permission]
    end

    test "get_permission!/1 returns the permission with given id" do
      permission = permission_fixture()
      assert AccessControls.get_permission!(permission.id) == permission
    end

    test "create_permission/1 with valid data creates a permission" do
      valid_attrs = %{entity: "some entity"}

      assert {:ok, %Permission{} = permission} = AccessControls.create_permission(valid_attrs)
      assert permission.entity == "some entity"
    end

    test "create_permission/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = AccessControls.create_permission(@invalid_attrs)
    end

    test "update_permission/2 with valid data updates the permission" do
      permission = permission_fixture()
      update_attrs = %{entity: "some updated entity"}

      assert {:ok, %Permission{} = permission} =
               AccessControls.update_permission(permission, update_attrs)

      assert permission.entity == "some updated entity"
    end

    test "update_permission/2 with invalid data returns error changeset" do
      permission = permission_fixture()

      assert {:error, %Ecto.Changeset{}} =
               AccessControls.update_permission(permission, @invalid_attrs)

      assert permission == AccessControls.get_permission!(permission.id)
    end

    test "delete_permission/1 deletes the permission" do
      permission = permission_fixture()
      assert {:ok, %Permission{}} = AccessControls.delete_permission(permission)
      assert_raise Ecto.NoResultsError, fn -> AccessControls.get_permission!(permission.id) end
    end

    test "change_permission/1 returns a permission changeset" do
      permission = permission_fixture()
      assert %Ecto.Changeset{} = AccessControls.change_permission(permission)
    end
  end
end
