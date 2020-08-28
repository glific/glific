defmodule GlificWeb.Schema.FlowTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  alias Glific.{
    Contacts,
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
  load_gql(:contact_flow, GlificWeb.Schema, "assets/gql/flows/contact_flow.gql")
  load_gql(:group_flow, GlificWeb.Schema, "assets/gql/flows/group_flow.gql")

  test "flows field returns list of flows" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    flows = get_in(query_data, [:data, "flows"])
    assert length(flows) > 0

    res = flows |> get_in([Access.all(), "name"]) |> Enum.find(fn x -> x == "Help Workflow" end)
    assert res == "Help Workflow"

    [flow | _] = flows
    assert get_in(flow, ["id"]) > 0
  end

  test "flows field returns list of flows filtered by keyword" do
    result = query_gql_by(:list, variables: %{"filter" => %{"keyword" => "timed"}})
    assert {:ok, query_data} = result

    flows = get_in(query_data, [:data, "flows"])
    assert length(flows) == 1
  end

  test "flow field id returns one flow or nil" do
    name = "Test Workflow"
    {:ok, flow} = Repo.fetch_by(Flow, %{name: name})

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
    name = "Flow Test Name"
    shortcode = "test shortcode"
    keywords = ["test_keyword", "test_keyword_2"]

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{"name" => name, "shortcode" => shortcode, "keywords" => keywords}
        }
      )

    assert {:ok, query_data} = result

    flow_name = get_in(query_data, [:data, "createFlow", "flow", "name"])
    assert flow_name == name

    # create message without required atributes
    result =
      query_gql_by(:create,
        variables: %{"input" => %{"name" => name}}
      )

    assert {:ok, query_data} = result

    assert "can't be blank" =
             get_in(query_data, [:data, "createFlow", "errors", Access.at(0), "message"])

    # create flow with existing keyword
    result =
      query_gql_by(:create,
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
    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})

    result = query_gql_by(:delete, variables: %{"id" => flow.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteFlow", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteFlow", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "Publish flow" do
    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})

    result = query_gql_by(:publish, variables: %{"id" => flow.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "publishFlow", "errors"]) == nil
    assert get_in(query_data, [:data, "publishFlow", "success"]) == true

    result = query_gql_by(:publish, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "publishFlow", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "Start flow for a contact" do
    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})
    [contact | _tail] = Contacts.list_contacts()

    result = query_gql_by(:contact_flow, variables: %{"id" => flow.id, "contactId" => contact.id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "startContactFlow", "errors", Access.at(0), "message"]) ==
             "Cannot send the message to the contact."

    # will add test for success with integration tests
  end

  test "Start flow for contacts of a group" do
    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Test Workflow"})
    group = Fixtures.group_fixture()

    result = query_gql_by(:group_flow, variables: %{"id" => flow.id, "groupId" => group.id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "startGroupFlow", "success"]) == true
  end
end
