defmodule Glific.Repo.Migrations.AddDuplicationFactorToAiEvaluations do
  use Ecto.Migration

  def change do
    alter table(:ai_evaluations) do
      add :duplication_factor, :integer,
        default: 1,
        null: false,
        comment: "Duplication factor used for this evaluation run"
    end
  end
end
