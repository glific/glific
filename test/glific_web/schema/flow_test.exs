defmodule GlificWeb.Schema.FlowTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Flows.Flow,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    SeedsDev.seed_flows()
    :ok
  end

  load_gql(:list, GlificWeb.Schema, "assets/gql/flows/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/flows/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/flows/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/flows/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/flows/delete.gql")
  load_gql(:publish, GlificWeb.Schema, "assets/gql/flows/publish.gql")

  def auth_query_gql_by(query, options \\ []) do
    user = Fixtures.user_fixture()
    options = Keyword.put_new(options, :context, %{:current_user => user})
    query_gql_by(query, options)
  end

  test "flows field returns list of flows" do
    result = auth_query_gql_by(:list)
    assert {:ok, query_data} = result

    flows = get_in(query_data, [:data, "flows"])
    assert length(flows) > 0

    res = flows |> get_in([Access.all(), "name"]) |> Enum.find(fn x -> x == "Help Workflow" end)
    assert res == "Help Workflow"

    [flow | _] = flows
    assert get_in(flow, ["id"]) > 0
  end

  test "flows field returns list of flows filtered by keyword" do
    result = auth_query_gql_by(:list, variables: %{"filter" => %{"keyword" => "help"}})
    assert {:ok, query_data} = result

    flows = get_in(query_data, [:data, "flows"])
    assert length(flows) == 1
  end

  test "flow field id returns one flow or nil" do
    name = "Test Workflow"
    {:ok, flow} = Repo.fetch_by(Flow, %{name: name})

    result = auth_query_gql_by(:by_id, variables: %{"id" => flow.id})
    assert {:ok, query_data} = result

    flow = get_in(query_data, [:data, "flow", "flow", "name"])
    assert flow == name

    result = auth_query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "flow", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create a flow and test possible scenarios and errors" do
    name = "Flow Test Name"
    shortcode = "test shortcode"
    keywords = ["test_keyword", "test_keyword_2"]

    result =
      auth_query_gql_by(:create,
        variables: %{
          "input" => %{"name" => name, "shortcode" => shortcode, "keywords" => keywords}
        }
      )

    assert {:ok, query_data} = result

    flow_name = get_in(query_data, [:data, "createFlow", "flow", "name"])
    assert flow_name == name

    # create message without required atributes
    result =
      auth_query_gql_by(:create,
        variables: %{"input" => %{"name" => name}}
      )

    assert {:ok, query_data} = result

    assert "can't be blank" =
             get_in(query_data, [:data, "createFlow", "errors", Access.at(0), "message"])

    # create flow with existing keyword
    result =
      auth_query_gql_by(:create,
        variables: %{
          "input" => %{
            "name" => "name_2",
            "shortcode" => "shortcode_2",
            "keywords" => ["test_keyword"]
          }
        }
      )

    assert {:ok, query_data} = result

    assert "keywords" = get_in(query_data, [:data, "createFlow", "errors", Access.at(0), "key"])

    assert "keywords [test_keyword] are already taken" =
             get_in(query_data, [:data, "createFlow", "errors", Access.at(0), "message"])
  end

  test "update a flow and test possible scenarios and errors" do
    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})

    name = "Flow Test Name"
    shortcode = "Test shortcode"

    result =
      auth_query_gql_by(:update,
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
    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})

    result = auth_query_gql_by(:delete, variables: %{"id" => flow.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteFlow", "errors"]) == nil

    result = auth_query_gql_by(:delete, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteFlow", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "Publish flow" do
    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})

    result = auth_query_gql_by(:publish, variables: %{"id" => flow.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "publishFlow", "errors"]) == nil
    assert get_in(query_data, [:data, "publishFlow", "success"]) == true

    result = auth_query_gql_by(:publish, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "publishFlow", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
