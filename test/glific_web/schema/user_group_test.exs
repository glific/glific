defmodule GlificWeb.Schema.UserGroupTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Groups.Group,
    Repo,
    Seeds.SeedsDev,
    Users.User
  }

  setup do
    SeedsDev.seed_users()
    SeedsDev.seed_groups()
    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/user_groups/create.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/user_groups/delete.gql")

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
