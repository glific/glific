defmodule Glific.Repo.Migrations.AddSyncStatusToSheets do
  use Ecto.Migration

  def change do
    alter table(:sheets) do
      add :sync_status, :string, default: "pending"
      add :failure_reason, :text
    end
  end
end
