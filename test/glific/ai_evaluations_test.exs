defmodule Glific.AIEvaluationsTest do
  @moduledoc false
  use Glific.DataCase, async: true

  import Ecto.Query

  alias Glific.{
    AIEvaluations,
    AIEvaluations.AIEvaluation,
    AIEvaluations.GoldenQA,
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Notifications,
    Notifications.Notification,
    Partners,
    Repo
  }

  @valid_attrs %{
    name: "test_experiment",
    status: :create_in_progress,
    golden_qa_id: 123,
    kaapi_evaluation_id: 123,
    assistant_config_version_id: 1
  }

  @invalid_attrs %{
    name: nil,
    status: nil,
    golden_qa_id: nil,
    assistant_config_version_id: nil,
    kaapi_evaluation_id: nil
  }

  describe "changeset/2" do
    test "changeset with valid attributes", %{organization_id: organization_id} do
      attrs = Map.put(@valid_attrs, :organization_id, organization_id)
      changeset = AIEvaluation.changeset(%AIEvaluation{}, attrs)
      assert changeset.valid?
    end

    test "changeset with invalid attributes", %{organization_id: organization_id} do
      attrs = Map.put(@invalid_attrs, :organization_id, organization_id)
      changeset = AIEvaluation.changeset(%AIEvaluation{}, attrs)
      refute changeset.valid?

      assert %{
               name: ["can't be blank"],
               golden_qa_id: ["can't be blank"],
               assistant_config_version_id: ["can't be blank"],
               status: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "changeset without organization_id" do
      changeset = AIEvaluation.changeset(%AIEvaluation{}, @valid_attrs)
      refute changeset.valid?
      assert %{organization_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset sets default status to create_in_progress", %{
      organization_id: organization_id
    } do
      attrs =
        @valid_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.delete(:status)

      changeset = AIEvaluation.changeset(%AIEvaluation{}, attrs)
      assert changeset.valid?
      assert changeset.data.status == :create_in_progress
    end

    test "changeset with optional fields", %{organization_id: organization_id} do
      attrs =
        @valid_attrs
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:failure_reason, "Something went wrong")
        |> Map.put(:kaapi_evaluation_id, 123)
        |> Map.put(:results, %{"score" => 0.95})

      changeset = AIEvaluation.changeset(%AIEvaluation{}, attrs)
      assert changeset.valid?
      assert changeset.changes.failure_reason == "Something went wrong"
      assert changeset.changes.results == %{"score" => 0.95}
    end
  end

  describe "update_ai_evaluation/2" do
    test "updates evaluation fields via changeset", %{organization_id: organization_id} do
      config_version = create_config_version(organization_id)
      evaluation = create_evaluation(organization_id, config_version.id)
      score = %{"score" => 0.92, "total" => 100}

      assert {:ok, updated} =
               AIEvaluations.update_ai_evaluation(evaluation, %{
                 status: :completed,
                 results: score,
                 kaapi_evaluation_id: 999
               })

      assert updated.status == :completed
      assert updated.results == score
      assert updated.kaapi_evaluation_id == 999
    end
  end

  describe "poll_and_update/1 - timeout logic" do
    setup %{organization_id: organization_id} do
      config_version = create_config_version(organization_id)
      %{config_version: config_version}
    end

    test "marks processing evaluation older than 1 hour as failed", %{
      organization_id: organization_id,
      config_version: config_version
    } do
      evaluation =
        create_evaluation(organization_id, config_version.id, %{status: :processing})
        |> backdate_evaluation(2)

      notification_count =
        Notifications.count_notifications(%{filter: %{organization_id: organization_id}})

      AIEvaluations.poll_and_update(organization_id)

      {:ok, updated} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert updated.status == :failed
      assert updated.failure_reason == "Evaluation timed out"

      assert Notifications.count_notifications(%{filter: %{organization_id: organization_id}}) ==
               notification_count + 1

      {:ok, notification} =
        Repo.fetch_by(Notification, %{organization_id: organization_id, category: "AI Evaluation"})

      assert notification.severity == Notifications.types().warning
      assert notification.message =~ "timed out"
    end

    test "does not timeout completed or failed evaluations", %{
      organization_id: organization_id,
      config_version: config_version
    } do
      completed =
        create_evaluation(organization_id, config_version.id, %{status: :completed})
        |> backdate_evaluation(2)

      failed =
        create_evaluation(organization_id, config_version.id, %{status: :failed})
        |> backdate_evaluation(2)

      AIEvaluations.poll_and_update(organization_id)

      {:ok, unchanged_completed} = Repo.fetch_by(AIEvaluation, %{id: completed.id})
      {:ok, unchanged_failed} = Repo.fetch_by(AIEvaluation, %{id: failed.id})
      assert unchanged_completed.status == :completed
      assert unchanged_failed.status == :failed
    end

    test "does not timeout recent processing evaluation", %{
      organization_id: organization_id,
      config_version: config_version
    } do
      evaluation = create_evaluation(organization_id, config_version.id, %{status: :processing})

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: %{data: %{status: "processing"}}}
      end)

      enable_kaapi(organization_id)
      AIEvaluations.poll_and_update(organization_id)

      {:ok, unchanged} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert unchanged.status == :processing
    end
  end

  describe "poll_and_update/1 - polling logic" do
    setup %{organization_id: organization_id} do
      enable_kaapi(organization_id)
      config_version = create_config_version(organization_id)
      evaluation = create_evaluation(organization_id, config_version.id, %{status: :processing})
      %{evaluation: evaluation, config_version: config_version}
    end

    test "updates evaluation to completed when Kaapi returns completed", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      summary_scores = [
        %{name: "Cosine Similarity", avg: 0.74, std: 0.1, data_type: "NUMERIC", total_pairs: 25}
      ]

      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: %{status: "completed", score: %{summary_scores: summary_scores, traces: []}}
          }
        }
      end)

      notification_count =
        Notifications.count_notifications(%{filter: %{organization_id: organization_id}})

      AIEvaluations.poll_and_update(organization_id)

      {:ok, updated} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert updated.status == :completed
      assert length(updated.results["summary_scores"]) == 1
      assert hd(updated.results["summary_scores"])["name"] == "Cosine Similarity"
      assert hd(updated.results["summary_scores"])["avg"] == 0.74

      assert Notifications.count_notifications(%{filter: %{organization_id: organization_id}}) ==
               notification_count + 1

      {:ok, notification} =
        Repo.fetch_by(Notification, %{organization_id: organization_id, category: "AI Evaluation"})

      assert notification.severity == Notifications.types().info
      assert notification.message =~ "completed successfully"
    end

    test "sets empty summary_scores when Kaapi completed response has no score", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: %{data: %{status: "completed"}}}
      end)

      AIEvaluations.poll_and_update(organization_id)

      {:ok, updated} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert updated.status == :completed
      assert updated.results == %{"summary_scores" => []}
    end

    test "updates evaluation to failed when Kaapi returns failed with reason", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{data: %{status: "failed", error_message: "Model inference error"}}
        }
      end)

      notification_count =
        Notifications.count_notifications(%{filter: %{organization_id: organization_id}})

      AIEvaluations.poll_and_update(organization_id)

      {:ok, updated} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert updated.status == :failed
      assert updated.failure_reason == "Model inference error"

      assert Notifications.count_notifications(%{filter: %{organization_id: organization_id}}) ==
               notification_count + 1

      {:ok, notification} =
        Repo.fetch_by(Notification, %{organization_id: organization_id, category: "AI Evaluation"})

      assert notification.severity == Notifications.types().warning
      assert notification.message =~ "Model inference error"
    end

    test "uses default failure reason when Kaapi failed response has no reason", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: %{data: %{status: "failed"}}}
      end)

      AIEvaluations.poll_and_update(organization_id)

      {:ok, updated} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert updated.status == :failed
      assert updated.failure_reason == "Evaluation failed"
    end

    test "leaves evaluation unchanged when Kaapi returns still processing", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 200, body: %{data: %{status: "processing"}}}
      end)

      AIEvaluations.poll_and_update(organization_id)

      {:ok, unchanged} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert unchanged.status == :processing
    end

    test "logs error and leaves evaluation unchanged when Kaapi returns 500", %{
      organization_id: organization_id,
      evaluation: evaluation
    } do
      Tesla.Mock.mock(fn %{method: :get} ->
        %Tesla.Env{status: 500, body: %{error: "Internal server error"}}
      end)

      AIEvaluations.poll_and_update(organization_id)

      {:ok, unchanged} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
      assert unchanged.status == :processing
    end
  end

  defp create_config_version(organization_id) do
    {:ok, assistant} =
      %Assistant{}
      |> Assistant.changeset(%{name: "Test Assistant", organization_id: organization_id})
      |> Repo.insert()

    {:ok, config_version} =
      %AssistantConfigVersion{}
      |> AssistantConfigVersion.changeset(%{
        assistant_id: assistant.id,
        prompt: "You are a helpful assistant.",
        provider: "openai",
        model: "gpt-4o",
        settings: %{"temperature" => 1.0},
        status: :ready,
        organization_id: organization_id
      })
      |> Repo.insert()

    config_version
  end

  defp create_golden_qa(organization_id) do
    {:ok, golden_qa} =
      %GoldenQA{}
      |> GoldenQA.changeset(%{
        name: "test_golden_qa_#{System.unique_integer([:positive])}",
        dataset_id: 1,
        organization_id: organization_id
      })
      |> Repo.insert()

    golden_qa
  end

  defp create_evaluation(organization_id, config_version_id, attrs \\ %{}) do
    golden_qa_id =
      Map.get_lazy(attrs, :golden_qa_id, fn -> create_golden_qa(organization_id).id end)

    base = %{
      name: "test_eval",
      status: :processing,
      golden_qa_id: golden_qa_id,
      kaapi_evaluation_id: 404,
      assistant_config_version_id: config_version_id,
      organization_id: organization_id
    }

    {:ok, evaluation} =
      %AIEvaluation{}
      |> AIEvaluation.changeset(Map.merge(base, attrs))
      |> Repo.insert()

    evaluation
  end

  defp backdate_evaluation(evaluation, hours_ago) do
    old_time = DateTime.utc_now() |> DateTime.add(-hours_ago, :hour) |> DateTime.truncate(:second)

    from(e in AIEvaluation, where: e.id == ^evaluation.id)
    |> Repo.update_all(set: [inserted_at: old_time])

    {:ok, updated_eval} = Repo.fetch_by(AIEvaluation, %{id: evaluation.id})
    updated_eval
  end

  defp enable_kaapi(organization_id) do
    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "kaapi",
      keys: %{},
      secrets: %{"api_key" => "sk_test_key"},
      is_active: true
    })

    organization_id |> Partners.get_organization!() |> Partners.fill_cache()
  end
end
