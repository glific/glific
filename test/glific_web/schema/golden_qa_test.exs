defmodule GlificWeb.Schema.GoldenQATest do
  @moduledoc """
  GraphQL integration tests for the Golden QA dataset list.
  """

  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.Fixtures

  load_gql(
    :list,
    GlificWeb.Schema,
    "assets/gql/ai_evaluations/list_golden_qas.gql"
  )

  load_gql(
    :by_id,
    GlificWeb.Schema,
    "assets/gql/ai_evaluations/get_golden_qa_dataset.gql"
  )

  setup %{organization_id: org_id} do
    FunWithFlags.enable(:ai_evaluations, for_actor: %{organization_id: org_id})
    :ok
  end

  test "goldenQas returns totalItems for each dataset", %{
    staff: user,
    organization_id: organization_id
  } do
    golden_qa =
      Fixtures.golden_qa_fixture(%{
        name: "dataset_with_items",
        dataset_id: 4242,
        total_items: 7,
        organization_id: organization_id
      })

    result = auth_query_gql_by(:list, user, variables: %{})

    assert {:ok, query_data} = result
    datasets = get_in(query_data, [:data, "goldenQas"])

    assert %{"totalItems" => 7} =
             Enum.find(datasets, &(&1["id"] == to_string(golden_qa.id)))
  end

  test "goldenQa returns every declared field off the record", %{
    staff: user,
    organization_id: organization_id
  } do
    golden_qa =
      Fixtures.golden_qa_fixture(%{
        name: "dataset_by_id",
        dataset_id: 4243,
        total_items: 11,
        file_name: "golden.csv",
        organization_id: organization_id
      })

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => golden_qa.id})

    assert {:ok, query_data} = result
    dataset = get_in(query_data, [:data, "goldenQa", "goldenQa"])

    assert dataset["datasetId"] == 4243
    assert dataset["totalItems"] == 11
    assert dataset["fileName"] == "golden.csv"
    assert dataset["signedUrl"] == nil
  end
end
