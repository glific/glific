defmodule Glific.Repo.Migrations.AddUniqueIndexAiEvaluationsName do
  use Ecto.Migration

  def change do
    create unique_index(:ai_evaluations, [:name, :organization_id])
  end
end
