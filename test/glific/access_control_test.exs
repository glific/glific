defmodule Glific.AccessControlTest do
  use Glific.DataCase

  alias Glific.{
    AccessControl,
    AccessControl.Permission,
    AccessControl.Role,
    Fixtures
  }

  describe "roles" do
    @invalid_attrs %{description: nil, is_reserved: nil, label: nil}

    test "list_roles/0 returns all roles", attrs do
      role = Fixtures.role_fixture(attrs)
      assert AccessControl.list_roles(%{organization_id: attrs.organization_id}) == [role]
    end

    test "get_role!/1 returns the role with given id", attrs do
      role = Fixtures.role_fixture(attrs)
      assert AccessControl.get_role!(role.id) == role
    end

    test "create_role/1 with valid data creates a role" do
      valid_attrs = %{description: "some description", is_reserved: true, label: "some label"}

      assert {:ok, %Role{} = role} = AccessControl.create_role(valid_attrs)
      assert role.description == "some description"
      assert role.is_reserved == true
      assert role.label == "some label"
    end

    test "create_role/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = AccessControl.create_role(@invalid_attrs)
    end

    test "update_role/2 with valid data updates the role", attrs do
      role = Fixtures.role_fixture(attrs)

      update_attrs = %{
        description: "some updated description",
        is_reserved: false,
        label: "some updated label"
      }

      assert {:ok, %Role{} = role} = AccessControl.update_role(role, update_attrs)
      assert role.description == "some updated description"
      assert role.is_reserved == false
      assert role.label == "some updated label"
    end

    test "update_role/2 with invalid data returns error changeset", attrs do
      role = Fixtures.role_fixture(attrs)
      assert {:error, %Ecto.Changeset{}} = AccessControl.update_role(role, @invalid_attrs)
      assert role == AccessControl.get_role!(role.id)
    end

    test "delete_role/1 deletes the role", attrs do
      role = Fixtures.role_fixture(attrs)
      assert {:ok, %Role{}} = AccessControl.delete_role(role)
      assert_raise Ecto.NoResultsError, fn -> AccessControl.get_role!(role.id) end
    end
  end

  describe "permissions" do
    @invalid_attrs %{entity: nil}

    test "list_permissions/0 returns all permissions", attrs do
      permission = Fixtures.permission_fixture(attrs)
      assert AccessControl.list_permissions() == [permission]
    end

    test "get_permission!/1 returns the permission with given id", attrs do
      permission = Fixtures.permission_fixture(attrs)
      assert AccessControl.get_permission!(permission.id) == permission
    end

    test "create_permission/1 with valid data creates a permission" do
      valid_attrs = %{entity: "some entity"}

      assert {:ok, %Permission{} = permission} = AccessControl.create_permission(valid_attrs)
      assert permission.entity == "some entity"
    end

    test "create_permission/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = AccessControl.create_permission(@invalid_attrs)
    end

    test "update_permission/2 with valid data updates the permission", attrs do
      permission = Fixtures.permission_fixture(attrs)
      update_attrs = %{entity: "some updated entity"}

      assert {:ok, %Permission{} = permission} =
               AccessControl.update_permission(permission, update_attrs)

      assert permission.entity == "some updated entity"
    end

    test "update_permission/2 with invalid data returns error changeset", attrs do
      permission = Fixtures.permission_fixture(attrs)

      assert {:error, %Ecto.Changeset{}} =
               AccessControl.update_permission(permission, @invalid_attrs)

      assert permission == AccessControl.get_permission!(permission.id)
    end

    test "delete_permission/1 deletes the permission", attrs do
      permission = Fixtures.permission_fixture(attrs)
      assert {:ok, %Permission{}} = AccessControl.delete_permission(permission)
      assert_raise Ecto.NoResultsError, fn -> AccessControl.get_permission!(permission.id) end
    end
  end
end
