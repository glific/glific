defmodule Glific.Repo.Migrations.UpdateAiEvaluationsGoldenQaFk do
  use Ecto.Migration

  def change do
    alter table(:ai_evaluations) do
      remove(:dataset_id)
      add(:golden_qa_id, references(:golden_qas, on_delete: :restrict), null: false)
    end

    create(index(:ai_evaluations, [:golden_qa_id]))
  end

  def down do
    alter table(:ai_evaluations) do
      remove(:golden_qa_id)
      add(:dataset_id, :integer, null: false)
    end

    # Drop the index created in `change`
    drop(index(:ai_evaluations, [:golden_qa_id]))
  end
end
