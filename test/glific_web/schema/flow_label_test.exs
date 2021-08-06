defmodule GlificWeb.Schema.FlowLabelTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Flows.FlowLabel,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    SeedsDev.seed_flow_labels()
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/flow_label/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/flow_label/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/flow_label/by_id.gql")

  test "flow_label id returns one flow_label or nil", %{staff: user} do
    name = "Age Group less than 10"
    {:ok, flow_label} = Repo.fetch_by(FlowLabel, %{name: name, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => flow_label.id})
    assert {:ok, query_data} = result
    flow_name = get_in(query_data, [:data, "flowLabel", "flowLabel", "name"])
    assert flow_name == name

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "flowLabel", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "flow_labels field returns list of flow_labels", %{staff: user} do
    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})
    assert {:ok, query_data} = result
    flow_labels = get_in(query_data, [:data, "flowLabels"])
    assert length(flow_labels) > 0
    [flow_label | _] = flow_labels
    assert get_in(flow_label, ["name"]) == "Age Group less than 10"
  end

  test "flow_labels field returns list of flow_labels in desc order", %{staff: user} do
    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "DESC"}})
    assert {:ok, query_data} = result

    flow_labels = get_in(query_data, [:data, "flowLabels"])
    assert length(flow_labels) > 0

    [flow_label | _] = flow_labels
    assert get_in(flow_label, ["name"]) == "New Activity"
  end

  test "flow_labels field returns list of flow_labels in various filters", %{staff: user} do
    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"name" => "New Activity"}})
    assert {:ok, query_data} = result
    flow_labels = get_in(query_data, [:data, "flowLabels"])
    assert length(flow_labels) > 0

    [flow_label | _] = flow_labels
    assert get_in(flow_label, ["name"]) == "New Activity"
  end

  test "flow_labels field obeys limit and offset", %{staff: user} do
    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 1, "offset" => 0}})

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "flowLabels"])) == 1

    result =
      auth_query_gql_by(:list, user, variables: %{"opts" => %{"limit" => 3, "offset" => 1}})

    assert {:ok, query_data} = result

    flow_labels = get_in(query_data, [:data, "flowLabels"])
    assert length(flow_labels) == 3
  end

  test "count returns the number of flow_labels", %{staff: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countFlowLabels"]) > 5

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"name" => "This flow label should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countFlowLabels"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"name" => "New Activity"}})

    assert get_in(query_data, [:data, "countFlowLabels"]) == 1
  end
end
