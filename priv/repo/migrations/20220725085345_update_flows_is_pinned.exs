defmodule Glific.Repo.Migrations.UpdateFlowsIsPinned do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add :is_pinned, :boolean, comment: "This is optional and depends on NGO usecase"
    end

    create index(:flows, [:is_pinned, :organization_id])
  end
end
