defmodule GlificWeb.Schema.UserTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias GlificWeb.API.V1.RegistrationController

  alias Glific.{
    Fixtures,
    Repo,
    Seeds.SeedsDev,
    Users,
    Users.User
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_users()
    :ok
  end

  load_gql(:list_roles, GlificWeb.Schema, "assets/gql/users/list_roles.gql")
  load_gql(:count, GlificWeb.Schema, "assets/gql/users/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/users/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/users/by_id.gql")
  load_gql(:current, GlificWeb.Schema, "assets/gql/users/current.gql")
  load_gql(:update_current, GlificWeb.Schema, "assets/gql/users/update_current.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/users/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/users/delete.gql")

  test "roles returns list of roles", %{manager: user} do
    result = auth_query_gql_by(:list_roles, user)
    assert {:ok, query_data} = result

    roles = get_in(query_data, [:data, "roles"])
    assert length(roles) >= 4
  end

  test "users returns list of users", %{staff: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    users = get_in(query_data, [:data, "users"])
    assert length(users) > 0

    res = users |> get_in([Access.all(), "name"]) |> Enum.find(fn x -> x == "NGO Staff" end)

    assert res == "NGO Staff"

    [user | _] = users
    assert user["groups"] == []
  end

  test "users returns list of users in asc order", %{staff: user} do
    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result

    users = get_in(query_data, [:data, "users"])
    assert length(users) > 0

    [user | _] = users

    assert get_in(user, ["name"]) == "Glific Admin"
  end

  test "users obeys limit and offset", %{staff: user} do
    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "users"])) == 1

    {:ok, query_data} = auth_query_gql_by(:list, user)
    users_count = get_in(query_data, [:data, "users"]) |> length

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"offset" => 1}})
    assert {:ok, query_data} = result

    users = get_in(query_data, [:data, "users"])
    assert length(users) == users_count - 1
  end

  test "count returns the number of users", %{staff: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    organization_id = Fixtures.get_org_id()

    assert get_in(query_data, [:data, "countUsers"]) ==
             Users.count_users(%{filter: %{organization_id: organization_id}})

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"name" => "This user should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countUsers"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"name" => "NGO Staff"}})

    assert get_in(query_data, [:data, "countUsers"]) == 1
  end

  test "user by id returns one user or nil", %{staff: user_auth} do
    name = "NGO Staff"
    {:ok, user} = Repo.fetch_by(User, %{name: name, organization_id: user_auth.organization_id})

    result = auth_query_gql_by(:by_id, user_auth, variables: %{"id" => user.id})
    assert {:ok, query_data} = result

    user = get_in(query_data, [:data, "user", "user"])
    assert user["name"] == name
    # isRestricted field should not be accesible by staff role
    assert user["isRestricted"] == nil

    result = auth_query_gql_by(:by_id, user_auth, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "user", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "current user returns current user", %{staff: user_auth} do
    result = auth_query_gql_by(:current, user_auth)
    assert {:ok, query_data} = result

    user = get_in(query_data, [:data, "currentUser", "user", "name"])
    assert user == user_auth.name
  end

  test "update current user with correct data", %{staff: user_auth} do
    name = "User Test Name New"

    result =
      auth_query_gql_by(:update_current, user_auth, variables: %{"input" => %{"name" => name}})

    assert {:ok, query_data} = result

    user_result = get_in(query_data, [:data, "updateCurrentUser", "user"])

    assert user_result["name"] == name
  end

  test "update current user password for different scenarios", %{staff: user} do
    user = user |> Repo.preload(:contact)
    Fixtures.otp_hsm_fixture()

    {:ok, otp} =
      RegistrationController.create_and_send_verification_code(
        user.organization_id,
        user.contact
      )

    name = "User Test Name New"

    result =
      auth_query_gql_by(:update_current, user,
        variables: %{
          "input" => %{"name" => name, "otp" => otp, "password" => "new_password"}
        }
      )

    assert {:ok, query_data} = result

    user_result = get_in(query_data, [:data, "updateCurrentUser", "user"])
    assert user_result["name"] == name

    # update with incorrect otp should give error
    result =
      auth_query_gql_by(:update_current, user,
        variables: %{
          "input" => %{"name" => name, "otp" => "incorrect_otp", "password" => "new_password"}
        }
      )

    assert {:ok, query_data} = result

    key = get_in(query_data, [:data, "updateCurrentUser", "errors", Access.at(0), "key"])
    assert key == "OTP"
  end

  test "delete a user", %{manager: user_auth} do
    user = Fixtures.user_fixture()

    result = auth_query_gql_by(:delete, user_auth, variables: %{"id" => user.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteUser", "errors"]) == nil

    result = auth_query_gql_by(:delete, user_auth, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteUser", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "update a user and test possible scenarios and errors", %{manager: user_auth} do
    {:ok, user} =
      Repo.fetch_by(User, %{name: "NGO Staff", organization_id: user_auth.organization_id})

    name = "User Test Name New"
    roles = ["Staff", "Admin"]

    group = Fixtures.group_fixture()

    result =
      auth_query_gql_by(:update, user_auth,
        variables: %{
          "id" => user.id,
          "input" => %{
            "name" => name,
            "roles" => roles,
            "groupIds" => [group.id],
            "isRestricted" => true
          }
        }
      )

    assert {:ok, query_data} = result

    user_result = get_in(query_data, [:data, "updateUser", "user"])

    assert user_result["name"] == name
    assert user_result["roles"] == roles
    assert user_result["groups"] == [%{"id" => "#{group.id}"}]
    assert user_result["isRestricted"] == true

    # update user groups
    group_2 = Fixtures.group_fixture(%{label: "new group"})
    roles = ["admin"]

    result =
      auth_query_gql_by(:update, user_auth,
        variables: %{
          "id" => user.id,
          "input" => %{
            "name" => name,
            "roles" => roles,
            "groupIds" => [group_2.id]
          }
        }
      )

    assert {:ok, query_data} = result

    user_result = get_in(query_data, [:data, "updateUser", "user"])

    assert user_result["groups"] == [%{"id" => "#{group_2.id}"}]
  end
end
