defmodule GlificWeb.Schema.Query.BSPTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    Glific.Seeds.seed_bsps()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/bsps/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/bsps/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/bsps/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/bsps/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/bsps/delete.gql")

  test "bsps field returns list of bsps" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    bsps = get_in(query_data, [:data, "bsps"])
    assert length(bsps) > 0

    res = bsps |> get_in([Access.all(), "name"]) |> Enum.find(fn x -> x == "Default BSP" end)

    assert res == "Default BSP"
  end

  test "bsp id returns one bsp or nil" do
    name = "Default BSP"
    {:ok, bsp} = Glific.Repo.fetch_by(Glific.Partners.BSP, %{name: name})

    result = query_gql_by(:by_id, variables: %{"id" => bsp.id})
    assert {:ok, query_data} = result

    bsp = get_in(query_data, [:data, "bsp", "bsp", "name"])
    assert bsp == name

    result = query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "bsp", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a bsp and test possible scenarios and errors" do
    name = "BSP Test Name"
    url = "Test url"
    api_end_point = "Test end point"

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"name" => name, "url" => url, "api_end_point" => api_end_point}}
      )

    assert {:ok, query_data} = result
    bsp = get_in(query_data, [:data, "createBsp", "bsp"])
    assert Map.get(bsp, "name") == name
    assert Map.get(bsp, "url") == url

    # try creating the same bsp twice
    _ =
      query_gql_by(:create,
        variables: %{"input" => %{"name" => name, "url" => url, "api_end_point" => api_end_point}}
      )

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"name" => name, "url" => url, "api_end_point" => api_end_point}}
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createBsp", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "update a bsp and test possible scenarios and errors" do
    {:ok, bsp} = Glific.Repo.fetch_by(Glific.Partners.BSP, %{name: "Default BSP"})

    name = "BSP Test Name"
    url = "Test url"
    api_end_point = "Test end point"

    result =
      query_gql_by(:update,
        variables: %{
          "id" => bsp.id,
          "input" => %{"name" => name, "url" => url, "api_end_point" => api_end_point}
        }
      )

    assert {:ok, query_data} = result

    new_name = get_in(query_data, [:data, "updateBsp", "bsp", "name"])
    assert new_name == name

    # create a temp bsp with a new name
    query_gql_by(:create,
      variables: %{
        "input" => %{"name" => "another bsp", "url" => url, "api_end_point" => api_end_point}
      }
    )

    # ensure we cannot update an existing bsp with the same name
    result =
      query_gql_by(:update,
        variables: %{
          "id" => bsp.id,
          "input" => %{"name" => "another bsp", "url" => url, "api_end_point" => api_end_point}
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "updateBsp", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "delete a bsp" do
    {:ok, bsp} = Glific.Repo.fetch_by(Glific.Partners.BSP, %{name: "Default BSP"})

    result = query_gql_by(:delete, variables: %{"id" => bsp.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteBsp", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteBsp", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
