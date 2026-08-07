defmodule GlificWeb.Schema.AIEvaluationImprovePromptTest do
  @moduledoc """
  GraphQL integration tests for the v2 evaluation prompt-improvement surface:
  - improveEvaluationPrompt mutation
  - full async loop (mutation -> callback creates config version)
  """

  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  import Tesla.Mock

  alias Glific.{
    AIEvaluations,
    AIEvaluations.AIEvaluation,
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Partners,
    Repo
  }

  load_gql(
    :improve,
    GlificWeb.Schema,
    "assets/gql/ai_evaluations/improve_prompt.gql"
  )

  defp enable_kaapi_and_v2(%{organization_id: org_id}) do
    {:ok, credential} =
      Partners.create_credential(%{
        organization_id: org_id,
        shortcode: "kaapi",
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"}
      })

    {:ok, _credential} =
      Partners.update_credential(credential, %{
        keys: %{},
        secrets: %{"api_key" => "sk_test_key"},
        is_active: true,
        organization_id: org_id,
        shortcode: "kaapi"
      })

    FunWithFlags.enable(:ai_evaluations, for_actor: %{organization_id: org_id})
    FunWithFlags.enable(:is_ai_evaluation_enabled, for_actor: %{organization_id: org_id})

    :ok
  end

  defp create_completed_evaluation(%{organization_id: org_id}) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{
        name: "Test Assistant",
        kaapi_uuid: "8a322023-2f28-4880-8bd3-bbe8611af901",
        organization_id: org_id
      })
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        prompt: "You are a helpful assistant.",
        provider: "openai",
        model: "gpt-4o",
        settings: %{},
        status: :ready,
        organization_id: org_id
      })
      |> Repo.insert()

    {:ok, golden_qa} =
      AIEvaluations.create_golden_qa(%{
        name: "improve_prompt_schema_test",
        dataset_id: 1,
        organization_id: org_id
      })

    {:ok, evaluation} =
      %AIEvaluation{}
      |> AIEvaluation.changeset(%{
        name: "test_evaluation_schema",
        status: :completed,
        kaapi_evaluation_id: 767,
        golden_qa_id: golden_qa.id,
        assistant_config_version_id: config_version.id,
        organization_id: org_id
      })
      |> Repo.insert()

    %{evaluation: evaluation, assistant: assistant}
  end

  defp kaapi_improve_prompt_mock do
    mock(fn %Tesla.Env{method: :post} ->
      %Tesla.Env{
        status: 200,
        body: %{success: true, data: %{job_id: "job_schema_test", status: "PENDING"}}
      }
    end)
  end

  describe "improveEvaluationPrompt mutation" do
    setup [:enable_kaapi_and_v2, :create_completed_evaluation]

    test "staff user can request a prompt recommendation and receives :pending", %{
      staff: user,
      evaluation: evaluation
    } do
      kaapi_improve_prompt_mock()

      result =
        auth_query_gql_by(:improve, user, variables: %{"evaluationId" => evaluation.id})

      assert {:ok, query_data} = result

      recommendation =
        get_in(query_data, [
          :data,
          "improveEvaluationPrompt",
          "improvePrompt"
        ])

      assert recommendation["status"] == "pending"
      assert get_in(query_data, [:data, "improveEvaluationPrompt", "errors"]) in [nil, []]
    end

    test "is rejected when the :is_ai_evaluation_enabled flag is off for the org", %{
      staff: user,
      organization_id: org_id,
      evaluation: evaluation
    } do
      FunWithFlags.disable(:is_ai_evaluation_enabled, for_actor: %{organization_id: org_id})

      result =
        auth_query_gql_by(:improve, user, variables: %{"evaluationId" => evaluation.id})

      assert {:ok, query_data} = result
      message = get_in(query_data, [:errors, Access.at(0), :message])
      assert message =~ "not enabled"
    end

    test "returns an error when the evaluation does not exist", %{staff: user} do
      result =
        auth_query_gql_by(:improve, user, variables: %{"evaluationId" => 999_999_999})

      assert {:ok, query_data} = result

      message =
        get_in(query_data, [
          :data,
          "improveEvaluationPrompt",
          "errors",
          Access.at(0),
          "message"
        ])

      assert message == "Evaluation not found."
    end
  end

  describe "full async loop" do
    setup [:enable_kaapi_and_v2, :create_completed_evaluation]

    test "improve -> callback creates a new :ready config version", %{
      staff: user,
      evaluation: evaluation,
      assistant: assistant
    } do
      kaapi_improve_prompt_mock()

      {:ok, mutation_data} =
        auth_query_gql_by(:improve, user, variables: %{"evaluationId" => evaluation.id})

      assert get_in(mutation_data, [
               :data,
               "improveEvaluationPrompt",
               "improvePrompt",
               "status"
             ]) == "pending"

      {:ok, new_config_version} =
        AIEvaluations.handle_improve_prompt_callback(%{
          "success" => true,
          "data" => %{
            "job_id" => "job_schema_test",
            "status" => "SUCCESS",
            "config_version" => %{
              "config_id" => assistant.kaapi_uuid,
              "version" => 6,
              "commit_message" => "[AI Generated] improved prompt",
              "config_blob" => %{
                "completion" => %{
                  "provider" => "openai",
                  "params" => %{"model" => "gpt-4o", "instructions" => "Fully improved prompt"}
                }
              }
            },
            "error_message" => nil
          }
        })

      assert new_config_version.status == :ready
      assert new_config_version.prompt == "Fully improved prompt"
      assert new_config_version.description == "[AI Generated] improved prompt"
    end
  end
end
