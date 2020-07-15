defmodule GlificWeb.Schema.UserTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  setup do
    Glific.SeedsDev.seed_users()
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/users/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/users/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/users/by_id.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/users/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/users/delete.gql")

  test "users returns list of users" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    users = get_in(query_data, [:data, "users"])
    assert length(users) > 0

    res =
      users |> get_in([Access.all(), "name"]) |> Enum.find(fn x -> x == "NGO Basic User 1" end)

    assert res == "NGO Basic User 1"
  end

  test "users returns list of users in asc order" do
    result = query_gql_by(:list, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result

    users = get_in(query_data, [:data, "users"])
    assert length(users) > 0

    [user | _] = users

    assert get_in(user, ["name"]) == "Glific Admin"
  end

  test "users obeys limit and offset" do
    result = query_gql_by(:list, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})
    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "users"])) == 1

    {:ok, query_data} = query_gql_by(:list)
    users_count = get_in(query_data, [:data, "users"]) |> length

    result = query_gql_by(:list, variables: %{"opts" => %{"offset" => 1}})
    assert {:ok, query_data} = result

    users = get_in(query_data, [:data, "users"])
    assert length(users) == users_count - 1
  end

  test "count returns the number of users" do
    {:ok, query_data} = query_gql_by(:count)
    assert get_in(query_data, [:data, "countUsers"]) == 3

    {:ok, query_data} =
      query_gql_by(:count,
        variables: %{"filter" => %{"name" => "This user should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countUsers"]) == 0

    {:ok, query_data} =
      query_gql_by(:count, variables: %{"filter" => %{"name" => "NGO Basic User 1"}})

    assert get_in(query_data, [:data, "countUsers"]) == 1
  end

  test "user by id returns one user or nil" do
    name = "NGO Basic User 1"
    {:ok, user} = Glific.Repo.fetch_by(Glific.Users.User, %{name: name})

    result = query_gql_by(:by_id, variables: %{"id" => user.id})
    assert {:ok, query_data} = result

    user = get_in(query_data, [:data, "user", "user", "name"])
    assert user == name

    result = query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "user", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "update a user and test possible scenarios and errors" do
    {:ok, user} = Glific.Repo.fetch_by(Glific.Users.User, %{name: "NGO Basic User 1"})

    name = "User Test Name New"
    roles = ["basic", "admin"]

    result =
      query_gql_by(:update,
        variables: %{"id" => user.id, "input" => %{"name" => name, "roles" => roles}}
      )

    assert {:ok, query_data} = result

    user_result = get_in(query_data, [:data, "updateUser", "user"])
    assert user_result["name"] == name
    assert user_result["roles"] == roles

    # update with incorrect role should give error
    roles = ["admin", "incorrect_role"]

    result =
      query_gql_by(:update,
        variables: %{"id" => user.id, "input" => %{"name" => name, "roles" => roles}}
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateUser", "errors", Access.at(0), "message"])
    assert message == "has an invalid entry"
  end

  test "delete a user" do
    {:ok, user} = Glific.Repo.fetch_by(Glific.Users.User, %{name: "NGO Basic User 1"})

    result = query_gql_by(:delete, variables: %{"id" => user.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteUser", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteUser", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
