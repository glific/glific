defmodule GlificWeb.Schema.UserGroupTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Groups.Group,
    Repo,
    Seeds.SeedsDev,
    Users.User
  }

  setup do
    SeedsDev.seed_users()
    Fixtures.group_fixture()
    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/user_groups/create.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/user_groups/delete.gql")
  load_gql(:update_group_users, GlificWeb.Schema, "assets/gql/user_groups/update_group_users.gql")
  load_gql(:update_user_groups, GlificWeb.Schema, "assets/gql/user_groups/update_user_groups.gql")

  test "update group users", %{user: auth_user} do
    label = "Default Group"

    {:ok, group} =
      Repo.fetch_by(Group, %{label: label, organization_id: auth_user.organization_id})

    user1 = Fixtures.user_fixture()
    user2 = Fixtures.user_fixture()

    # add group users
    result =
      auth_query_gql_by(:update_group_users, auth_user,
        variables: %{
          "input" => %{
            "group_id" => group.id,
            "add_user_ids" => [user1.id, user2.id],
            "delete_user_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    group_users = get_in(query_data, [:data, "updateGroupUsers", "groupUsers"])
    assert length(group_users) == 2

    # delete group users
    result =
      auth_query_gql_by(:update_group_users, auth_user,
        variables: %{
          "input" => %{
            "group_id" => group.id,
            "add_user_ids" => [],
            "delete_user_ids" => [user1.id]
          }
        }
      )

    assert {:ok, query_data} = result
    number_deleted = get_in(query_data, [:data, "updateGroupUsers", "numberDeleted"])
    assert number_deleted == 1

    # test for incorrect user id
    result =
      auth_query_gql_by(:update_group_users, auth_user,
        variables: %{
          "input" => %{
            "group_id" => group.id,
            "add_user_ids" => ["-1"],
            "delete_user_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    group_users = get_in(query_data, [:data, "updateGroupUsers", "groupUsers"])
    assert group_users == []
  end

  test "update user groups", %{user: user} do
    name = "NGO Admin"
    {:ok, user} = Repo.fetch_by(User, %{name: name, organization_id: user.organization_id})

    group1 = Fixtures.group_fixture(%{label: "New Group 1"})
    group2 = Fixtures.group_fixture(%{label: "New Group 2"})

    # add user groups
    result =
      auth_query_gql_by(:update_user_groups, user,
        variables: %{
          "input" => %{
            "user_id" => user.id,
            "add_group_ids" => [group1.id, group2.id],
            "delete_group_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    user_groups = get_in(query_data, [:data, "updateUserGroups", "userGroups"])
    assert length(user_groups) == 2

    # delete user groups
    result =
      auth_query_gql_by(:update_user_groups, user,
        variables: %{
          "input" => %{
            "user_id" => user.id,
            "add_group_ids" => [],
            "delete_group_ids" => [group1.id]
          }
        }
      )

    assert {:ok, query_data} = result
    number_deleted = get_in(query_data, [:data, "updateUserGroups", "numberDeleted"])
    assert number_deleted == 1

    # test for incorrect group id
    result =
      auth_query_gql_by(:update_user_groups, user,
        variables: %{
          "input" => %{
            "user_id" => user.id,
            "add_group_ids" => ["-1"],
            "delete_group_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    user_groups = get_in(query_data, [:data, "updateUserGroups", "userGroups"])
    assert user_groups == []
  end

  test "create a user group and test possible scenarios and errors", %{user: auth_user} do
    label = "Default Group"

    {:ok, group} =
      Repo.fetch_by(Group, %{label: label, organization_id: auth_user.organization_id})

    name = "NGO Basic User 1"
    {:ok, user} = Repo.fetch_by(User, %{name: name, organization_id: auth_user.organization_id})

    result =
      auth_query_gql_by(:create, auth_user,
        variables: %{"input" => %{"user_id" => user.id, "group_id" => group.id}}
      )

    assert {:ok, query_data} = result

    user_group = get_in(query_data, [:data, "createUserGroup", "user_group"])

    assert user_group["user"]["id"] |> String.to_integer() == user.id
    assert user_group["group"]["id"] |> String.to_integer() == group.id

    # try creating the same user group entry twice
    result =
      auth_query_gql_by(:create, auth_user,
        variables: %{"input" => %{"user_id" => user.id, "group_id" => group.id}}
      )

    assert {:ok, query_data} = result

    user = get_in(query_data, [:data, "createUserGroup", "errors", Access.at(0), "message"])
    assert user == "has already been taken"
  end

  test "delete a user group", %{user: auth_user} do
    label = "Default Group"

    {:ok, group} =
      Repo.fetch_by(Group, %{label: label, organization_id: auth_user.organization_id})

    name = "NGO Basic User 1"
    {:ok, user} = Repo.fetch_by(User, %{name: name, organization_id: auth_user.organization_id})

    {:ok, query_data} =
      auth_query_gql_by(:create, auth_user,
        variables: %{"input" => %{"user_id" => user.id, "group_id" => group.id}}
      )

    user_group_id = get_in(query_data, [:data, "createUserGroup", "user_group", "id"])

    result = auth_query_gql_by(:delete, auth_user, variables: %{"id" => user_group_id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteUserGroup", "errors"]) == nil

    # try to delete incorrect entry
    result = auth_query_gql_by(:delete, auth_user, variables: %{"id" => user_group_id})
    assert {:ok, query_data} = result

    user = get_in(query_data, [:data, "deleteUserGroup", "errors", Access.at(0), "message"])
    assert user == "Resource not found"
  end
end
