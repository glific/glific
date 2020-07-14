defmodule GlificWeb.Schema.FlowTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  alias Glific.{Flows.Flow}

  setup do
    Glific.SeedsDev.seed_flows()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/flows/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/flows/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/flows/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/flows/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/flows/delete.gql")

  test "flows field returns list of flows" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    flows = get_in(query_data, [:data, "flows"])
    assert length(flows) > 0

    res = flows |> get_in([Access.all(), "name"]) |> Enum.find(fn x -> x == "Help Workflow" end)
    assert res == "Help Workflow"

    [flow | _] = flows
    assert get_in(flow, ["language", "id"]) > 0
  end

  test "flow field id returns one flow or nil" do
    name = "Test Workflow"
    {:ok, flow} = Glific.Repo.fetch_by(Glific.Flows.Flow, %{name: name})

    result = query_gql_by(:by_id, variables: %{"id" => flow.id})
    assert {:ok, query_data} = result

    flow = get_in(query_data, [:data, "flow", "flow", "name"])
    assert flow == name

    result = query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "flow", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a flow and test possible scenarios and errors" do
    name = "Test Workflow"
    {:ok, flow} = Glific.Repo.fetch_by(Flow, %{name: name})
    language_id = flow.language_id

    name = "Flow Test Name"

    result =
      query_gql_by(:create,
        variables: %{"input" => %{"name" => name, "languageId" => language_id}}
      )

    assert {:ok, query_data} = result

    flow_name = get_in(query_data, [:data, "createFlow", "flow", "name"])
    assert flow_name == name
  end

  test "update a flow and test possible scenarios and errors" do
    {:ok, flow} = Glific.Repo.fetch_by(Flow, %{name: "Test Workflow"})

    name = "Flow Test Name"
    shortcode = "Test shortcode"

    result =
      query_gql_by(:update,
        variables: %{
          "id" => flow.id,
          "input" => %{"name" => name, "shortcode" => shortcode}
        }
      )

    assert {:ok, query_data} = result

    new_name = get_in(query_data, [:data, "updateFlow", "flow", "name"])
    assert new_name == name
  end

  test "delete a flow" do
    {:ok, flow} = Glific.Repo.fetch_by(Flow, %{name: "Test Workflow"})

    result = query_gql_by(:delete, variables: %{"id" => flow.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteFlow", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteFlow", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
