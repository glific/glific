defmodule GlificWeb.Schema.RoleTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    AccessControl.Role,
    Repo
  }

  load_gql(:list, GlificWeb.Schema, "assets/gql/roles/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/roles/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/roles/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/roles/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/roles/delete.gql")
  load_gql(:count, GlificWeb.Schema, "assets/gql/roles/count.gql")

  test "role field id returns one role or nil", %{staff: user} do
    label = "Admin"
    {:ok, role} = Repo.fetch_by(Role, %{label: label, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => role.id})
    assert {:ok, query_data} = result

    role_name = get_in(query_data, [:data, "accessRole", "accessRole", "label"])
    assert role_name == label

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "accessRole", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "roles field returns list of roles", %{staff: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    roles = get_in(query_data, [:data, "accessRoles"])
    assert length(roles) > 0

    result = roles |> get_in([Access.all(), "label"]) |> Enum.find(fn role -> role == "Admin" end)
    assert result == "Admin"
  end

  test "create a role and test possible scenarios and errors", %{manager: user} do
    # Create a new role
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{"label" => "Mentor", "description" => "new custom organization role"}
        }
      )

    assert {:ok, query_data} = result
    role_label = get_in(query_data, [:data, "createAccessRole", "accessRole", "label"])
    assert role_label == "Mentor"

    role_description =
      get_in(query_data, [:data, "createAccessRole", "accessRole", "description"])

    assert role_description == "new custom organization role"
    assert false == get_in(query_data, [:data, "createAccessRole", "accessRole", "isReserved"])

    # create message without required attributes
    result = auth_query_gql_by(:create, user, variables: %{"input" => %{}})

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "createAccessRole", "errors", Access.at(0), "message"]) =~
             "can't be blank"

    # create message with duplicate label should throw error
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{"label" => "Admin", "description" => "new custom organization role"}
        }
      )

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "createAccessRole", "errors", Access.at(0), "message"]) =~
             "has already been taken"
  end

  test "update a role and test possible scenarios and errors", %{manager: user} do
    {:ok, role} = Repo.fetch_by(Role, %{label: "Admin", organization_id: user.organization_id})

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => role.id,
          "input" => %{"label" => "Super Admin"}
        }
      )

    assert {:ok, query_data} = result
    new_name = get_in(query_data, [:data, "updateAccessRole", "accessRole", "label"])
    assert new_name == "Super Admin"
  end

  test "delete a role", %{manager: user} do
    {:ok, role} = Repo.fetch_by(Role, %{label: "Admin", organization_id: user.organization_id})

    result = auth_query_gql_by(:delete, user, variables: %{"id" => role.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteAccessRole", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteAccessRole", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "count returns the number of roles", %{staff: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countAccessRoles"]) > 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"label" => "This role should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countAccessRoles"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"label" => "Admin"}})

    assert get_in(query_data, [:data, "countAccessRoles"]) == 1
  end
end
