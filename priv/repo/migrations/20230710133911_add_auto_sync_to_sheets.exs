defmodule Glific.Repo.Migrations.AddTagsToFlows do
  use Ecto.Migration

  def change do
    alter table(:sheets) do
      add(:auto_sync, :boolean, default: false, comment: "Auto Sync Sheets data in some interval")
    end
  end
end
