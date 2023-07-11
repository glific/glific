defmodule Glific.Repo.Migrations.AddAutoSyncToSheets do
  use Ecto.Migration

  def change do
    alter table(:sheets) do
      add(:auto_sync, :boolean, default: false, comment: "Auto Sync Sheets data in some interval")
    end
  end
end
