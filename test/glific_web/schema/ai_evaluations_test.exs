defmodule GlificWeb.Schema.AIEvaluationsTest do
  @moduledoc """
  Test suite for GraphQL API related to AI Evaluations and Golden QA management.
  """
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.Partners

  load_gql(
    :create_evaluation,
    GlificWeb.Schema,
    "assets/gql/ai_evaluations/create_evaluation.gql"
  )

  describe "create_evaluation/3" do
    setup :enable_ai_evaluations

    test "creates and returns evaluation on success", %{staff: user} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: %{data: %{status: "processing"}}
          }
      end)

      {:ok, query_data} =
        auth_query_gql_by(:create_evaluation, user,
          variables: %{
            "input" => %{
              "datasetId" => "1",
              "experimentName" => "test_experiment",
              "configId" => "2",
              "configVersion" => "1"
            }
          }
        )

      assert query_data.data["createEvaluation"]["status"] == "processing"
    end

    test "returns error when Kaapi API fails", %{staff: user} do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 500,
            body: %{error: "Internal server error"}
          }
      end)

      {:ok, query_data} =
        auth_query_gql_by(:create_evaluation, user,
          variables: %{
            "input" => %{
              "datasetId" => "1",
              "experimentName" => "test_experiment",
              "configId" => "2",
              "configVersion" => "1"
            }
          }
        )

      assert query_data.data["createEvaluation"] == nil
      assert [error | _] = query_data.errors
      assert error[:message] =~ "Internal server error"
    end

    test "returns error on timeout", %{staff: user} do
      Tesla.Mock.mock(fn
        %{method: :post} -> {:error, :timeout}
      end)

      {:ok, query_data} =
        auth_query_gql_by(:create_evaluation, user,
          variables: %{
            "input" => %{
              "datasetId" => "1",
              "experimentName" => "test_experiment",
              "configId" => "2",
              "configVersion" => "1"
            }
          }
        )

      assert query_data.data["createEvaluation"] == nil
      assert [error | _] = query_data.errors
      assert error[:message] == "Timeout occurred, please try again."
    end
  end

  defp enable_ai_evaluations(%{organization_id: organization_id}) do
    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "kaapi",
      keys: %{},
      secrets: %{"api_key" => "sk_test_key"},
      is_active: true
    })

    FunWithFlags.enable(:ai_evaluations,
      for_actor: %{organization_id: organization_id}
    )

    :ok
  end
end
