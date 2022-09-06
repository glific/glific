defmodule Glific.AccessControlTest do
  use Glific.DataCase

  alias Glific.{
    AccessControl,
    AccessControl.Permission,
    AccessControl.Role,
    Fixtures,
    Flows,
    Groups,
    Seeds.SeedsDev,
    Users
  }

  describe "roles" do
    @invalid_attrs %{description: nil, is_reserved: nil, label: nil}
    @valid_attrs %{
      description: "some more organization description",
      is_reserved: false,
      label: "some more organization label"
    }
    @valid_more_attrs %{
      description: "some more description",
      is_reserved: false,
      label: "some more label"
    }

    test "list_roles/0 returns all reserved roles when flag is disabled", attrs do
      FunWithFlags.disable(:roles_and_permission,
        for_actor: %{organization_id: attrs.organization_id}
      )

      Fixtures.role_fixture(attrs)

      assert AccessControl.count_roles(%{filter: attrs, organization_id: attrs.organization_id}) ==
               4
    end

    test "list_roles/0 returns all roles", attrs do
      FunWithFlags.enable(:roles_and_permission,
        for_actor: %{organization_id: attrs.organization_id}
      )

      role = Fixtures.role_fixture(attrs)

      assert Enum.filter(
               AccessControl.list_roles(%{organization_id: attrs.organization_id}),
               fn r -> r.label == role.label end
             ) ==
               [role]
    end

    test "list_roles/0 returns with filtered data", attrs do
      FunWithFlags.enable(:roles_and_permission,
        for_actor: %{organization_id: attrs.organization_id}
      )

      role = Fixtures.role_fixture(attrs)

      assert AccessControl.list_roles(%{
               organization_id: attrs.organization_id,
               filter: %{description: role.description}
             }) == [role]

      assert AccessControl.list_roles(%{
               organization_id: attrs.organization_id,
               filter: %{is_reserved: role.is_reserved}
             }) == [role]
    end

    test "organization_roles/1 returns all organization roles",
         %{organization_id: organization_id} = attrs do
      FunWithFlags.enable(:roles_and_permission, for_actor: %{organization_id: organization_id})

      assert {:ok, _role} =
               attrs
               |> Map.merge(@valid_attrs)
               |> AccessControl.create_role()

      assert ["some more organization label"] =
               AccessControl.organization_roles(%{organization_id: organization_id})
    end

    test "get_role!/1 returns the role with given id", attrs do
      role = Fixtures.role_fixture(attrs)
      assert AccessControl.get_role!(role.id) == role
    end

    test "create_role/1 with valid data creates a role", attrs do
      valid_attrs = %{
        description: "some description",
        is_reserved: true,
        label: "some label",
        organization_id: attrs.organization_id
      }

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

    test "count_roles/1 returns count of all roles",
         %{organization_id: _organization_id} = attrs do
      FunWithFlags.enable(:roles_and_permission,
        for_actor: %{organization_id: attrs.organization_id}
      )

      role_count =
        AccessControl.count_roles(%{filter: attrs, organization_id: attrs.organization_id})

      _ = Fixtures.role_fixture(attrs)

      assert AccessControl.count_roles(%{filter: attrs, organization_id: attrs.organization_id}) ==
               role_count + 1

      _ = Fixtures.role_fixture(Map.merge(attrs, @valid_more_attrs))

      assert AccessControl.count_roles(%{filter: attrs, organization_id: attrs.organization_id}) ==
               role_count + 2
    end

    test "list_flows/1 returns list of flows assigned to user", attrs do
      FunWithFlags.disable(:roles_and_permission,
        for_actor: %{organization_id: attrs.organization_id}
      )

      SeedsDev.seed_test_flows()
      default_role = Fixtures.role_fixture(attrs)
      default_role_id = to_string(default_role.id)

      user = Fixtures.user_fixture(%{roles: ["none"]})

      Users.update_user(user, %{
        add_role_ids: [default_role_id],
        delete_role_ids: [],
        organization_id: attrs.organization_id
      })

      [flow | _] = Flows.list_flows(%{filter: %{name: "Test Workflow"}})

      FunWithFlags.enable(:roles_and_permission,
        for_actor: %{organization_id: attrs.organization_id}
      )

      Flows.update_flow(flow, %{
        add_role_ids: [default_role_id],
        delete_role_ids: [],
        name: flow.name,
        organization_id: attrs.organization_id
      })

      assert [] == Flows.list_flows(%{})
      Repo.put_current_user(user)
      [assigned_flow] = Flows.list_flows(%{})
      assert assigned_flow == flow

      # Creating new flow is assigned to same role by default
      name = "New Test Workflow"

      Flows.create_flow(%{
        add_role_ids: [default_role_id],
        delete_role_ids: [],
        name: name,
        organization_id: attrs.organization_id
      })

      [_f1, f2 | _] = Flows.list_flows(%{})
      assert f2.name == name
    end

    test "list_groups/1 returns list of flows assigned to user", attrs do
      FunWithFlags.disable(:roles_and_permission,
        for_actor: %{organization_id: attrs.organization_id}
      )

      SeedsDev.seed_groups()
      default_role = Fixtures.role_fixture(attrs)
      default_role_id = to_string(default_role.id)

      user = Fixtures.user_fixture(%{roles: ["none"]})

      Users.update_user(user, %{
        add_role_ids: [default_role_id],
        delete_role_ids: [],
        organization_id: attrs.organization_id
      })

      [group | _] = Groups.list_groups(%{filter: %{label: "Default Group"}})

      FunWithFlags.enable(:roles_and_permission,
        for_actor: %{organization_id: attrs.organization_id}
      )

      Groups.update_group(group, %{
        add_role_ids: [default_role_id],
        delete_role_ids: [],
        label: group.label,
        organization_id: attrs.organization_id
      })

      assert [] == Groups.list_groups(%{})
      Repo.put_current_user(user)
      [assigned_group] = Groups.list_groups(%{})
      assert assigned_group == group

      # Creating new collection is assigned to same role by default
      label = "New Test Collection"

      Groups.create_group(%{
        add_role_ids: [default_role_id],
        delete_role_ids: [],
        label: label,
        organization_id: attrs.organization_id
      })

      [_g1, g2 | _] = Groups.list_groups(%{})
      assert g2.label == label
    end

    test "do_check_access/3 should return error tuple when entity type is unknown", _attrs do
      user = Repo.get_current_user()
      assert {:error, msg} = AccessControl.do_check_access(%{}, :unknown, user)
      assert msg == "Unknown entity type unknown"
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
