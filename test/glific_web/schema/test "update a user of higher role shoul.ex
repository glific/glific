test "update a user of higher role should give an errors", %{manager: user_auth} do
  {:ok, user} =
    Repo.fetch_by(User, %{name: "NGO Staff", organization_id: user_auth.organization_id})

  name = "User Test Name New"
  roles = ["Admin"]

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

  error = get_in(query_data, [:errors]) |> hd

  assert error.message == "Does not have access to the user"
end
