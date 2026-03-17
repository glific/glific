defmodule Glific.AIEvaluationsTest do
  @moduledoc false
  use Glific.DataCase, async: true

  alias Glific.AIEvaluations.AIEvaluation

  @valid_attrs %{
    name: "test_experiment",
    status: :create_in_progress,
    dataset_id: "dataset_abc123",
    config_id: "config_abc123",
    config_version: "version_abc123",
    kaapi_evaluation_id: "eval_abc123"
  }

  @invalid_attrs %{
    name: nil,
    status: nil,
    dataset_id: nil,
    config_id: nil,
    config_version: nil,
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
               dataset_id: ["can't be blank"],
               config_id: ["can't be blank"],
               config_version: ["can't be blank"],
               kaapi_evaluation_id: ["can't be blank"]
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
        |> Map.put(:results, %{"score" => 0.95})

      changeset = AIEvaluation.changeset(%AIEvaluation{}, attrs)
      assert changeset.valid?
      assert changeset.changes.failure_reason == "Something went wrong"
      assert changeset.changes.results == %{"score" => 0.95}
    end
  end
end
