defmodule GlificWeb.Schema.GroupTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  alias Glific.Fixtures

  setup do
    Fixtures.group_fixture()
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/groups/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/groups/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/groups/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/groups/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/groups/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/groups/delete.gql")

  test "groups field returns list of groups" do
    result = query_gql_by(:list, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result

    groups = get_in(query_data, [:data, "groups"])
    assert length(groups) > 0

    [group | _] = groups
    assert get_in(group, ["label"]) == "Default Group"
  end

  test "groups field returns list of groups in desc order" do
    result = query_gql_by(:list, variables: %{"opts" => %{"order" => "DESC"}})
    assert {:ok, query_data} = result

    groups = get_in(query_data, [:data, "groups"])
    assert length(groups) > 0

    [group | _] = groups
    assert get_in(group, ["label"]) == "Restricted Group"
  end

  test "groups field returns list of groups in various filters" do
    result = query_gql_by(:list, variables: %{"filter" => %{"label" => "Restricted Group"}})
    assert {:ok, query_data} = result

    groups = get_in(query_data, [:data, "groups"])
    assert length(groups) > 0

    [group | _] = groups
    assert get_in(group, ["label"]) == "Restricted Group"
  end

  test "groups field obeys limit and offset" do
    result = query_gql_by(:list, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})
    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "groups"])) == 1

    result = query_gql_by(:list, variables: %{"opts" => %{"limit" => 3, "offset" => 1}})
    assert {:ok, query_data} = result

    groups = get_in(query_data, [:data, "groups"])
    assert length(groups) <= 3
  end

  test "count returns the number of groups" do
    {:ok, query_data} = query_gql_by(:count)
    assert get_in(query_data, [:data, "countGroups"]) >= 2

    {:ok, query_data} =
      query_gql_by(:count,
        variables: %{"filter" => %{"label" => "This group should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countGroups"]) == 0

    {:ok, query_data} =
      query_gql_by(:count, variables: %{"filter" => %{"label" => "Default Group"}})

    assert get_in(query_data, [:data, "countGroups"]) == 1
  end

  test "group id returns one group or nil" do
    label = "Default Group"
    {:ok, group} = Glific.Repo.fetch_by(Glific.Groups.Group, %{label: label})

    result = query_gql_by(:by_id, variables: %{"id" => group.id})
    assert {:ok, query_data} = result

    group_label = get_in(query_data, [:data, "group", "group", "label"])
    assert group_label == label

    result = query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "group", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a group and test possible scenarios and errors" do
    result =
      query_gql_by(:create,
        variables: %{"input" => %{"label" => "Test Group"}}
      )

    assert {:ok, query_data} = result
    assert query_data[:data]["createGroup"]["errors"] == nil
    assert query_data[:data]["createGroup"]["group"]["label"] == "Test Group"

    # try creating the same group twice
    _ =
      query_gql_by(:create,
        variables: %{"input" => %{"label" => "test label"}}
      )

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"label" => "test label"}}
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createGroup", "errors", Access.at(0), "message"])
    assert query_data[:data]["createGroup"]["errors"] != nil
    assert message == "has already been taken"
  end

  test "update a group and test possible scenarios and errors" do
    label = "Default Group"
    {:ok, group} = Glific.Repo.fetch_by(Glific.Groups.Group, %{label: label})

    result =
      query_gql_by(:update,
        variables: %{"id" => group.id, "input" => %{"label" => "New Test Group Label"}}
      )

    assert {:ok, query_data} = result

    label = get_in(query_data, [:data, "updateGroup", "group", "label"])
    assert label == "New Test Group Label"

    result =
      query_gql_by(:update,
        variables: %{
          "id" => group.id,
          "input" => %{"label" => "Restricted Group"}
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateGroup", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "delete a group" do
    label = "Default Group"
    {:ok, group} = Glific.Repo.fetch_by(Glific.Groups.Group, %{label: label})

    result = query_gql_by(:delete, variables: %{"id" => group.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteGroup", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => group.id})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteGroup", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
