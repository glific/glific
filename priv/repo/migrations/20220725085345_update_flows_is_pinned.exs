defmodule Glific.Repo.Migrations.UpdateFlowsIsPinned do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add :is_pinned, :boolean,
        default: false,
        comment: "This is for showing the pinned flows at the top of flow screen"
    end

    create index(:flows, [:is_pinned, :organization_id])
  end
end
