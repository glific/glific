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
end
