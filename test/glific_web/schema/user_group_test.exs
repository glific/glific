defmodule GlificWeb.Schema.UserGroupTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Groups,
    Groups.Group,
    Repo,
    Seeds.SeedsDev,
    Users,
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

  test "update group users" do
    label = "Default Group"
    {:ok, group} = Repo.fetch_by(Group, %{label: label})

    [user1, user2 | _] = Users.list_users()

    # add group users
    result =
      query_gql_by(:update_group_users,
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
      query_gql_by(:update_group_users,
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
      query_gql_by(:update_group_users,
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

  test "update user groups" do
    name = "NGO Admin"
    {:ok, user} = Repo.fetch_by(User, %{name: name})

    [group1, group2 | _] = Groups.list_groups()

    # add user groups
    result =
      query_gql_by(:update_user_groups,
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
      query_gql_by(:update_user_groups,
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
      query_gql_by(:update_user_groups,
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

  test "create a user group and test possible scenarios and errors" do
    label = "Default Group"
    {:ok, group} = Repo.fetch_by(Group, %{label: label})
    name = "NGO Basic User 1"
    {:ok, user} = Repo.fetch_by(User, %{name: name})

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"user_id" => user.id, "group_id" => group.id}}
      )

    assert {:ok, query_data} = result

    user_group = get_in(query_data, [:data, "createUserGroup", "user_group"])

    assert user_group["user"]["id"] |> String.to_integer() == user.id
    assert user_group["group"]["id"] |> String.to_integer() == group.id

    # try creating the same user group entry twice
    result =
      query_gql_by(:create,
        variables: %{"input" => %{"user_id" => user.id, "group_id" => group.id}}
      )

    assert {:ok, query_data} = result

    user = get_in(query_data, [:data, "createUserGroup", "errors", Access.at(0), "message"])
    assert user == "has already been taken"
  end

  test "delete a user group" do
    label = "Default Group"
    {:ok, group} = Repo.fetch_by(Group, %{label: label})
    name = "NGO Basic User 1"
    {:ok, user} = Repo.fetch_by(User, %{name: name})

    {:ok, query_data} =
      query_gql_by(:create,
        variables: %{"input" => %{"user_id" => user.id, "group_id" => group.id}}
      )

    user_group_id = get_in(query_data, [:data, "createUserGroup", "user_group", "id"])

    result = query_gql_by(:delete, variables: %{"id" => user_group_id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteUserGroup", "errors"]) == nil

    # try to delete incorrect entry
    result = query_gql_by(:delete, variables: %{"id" => user_group_id})
    assert {:ok, query_data} = result

    user = get_in(query_data, [:data, "deleteUserGroup", "errors", Access.at(0), "message"])
    assert user == "Resource not found"
  end
end
