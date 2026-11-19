defmodule Glific.Repo.Migrations.AddLastEvaluationRunToAssistants do
  use Ecto.Migration

  def change do
    alter table(:assistants) do
      add :last_evaluation_run_id, references(:ai_evaluations, on_delete: :nilify_all),
        comment:
          "Most recent AI evaluation completed against this assistant's active config version"
    end

    create index(:assistants, [:last_evaluation_run_id])
  end
end
