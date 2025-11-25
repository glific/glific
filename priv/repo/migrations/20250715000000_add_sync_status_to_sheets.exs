defmodule Glific.Repo.Migrations.AddSyncStatusToSheets do
  use Ecto.Migration

  def change do
    Glific.Enums.SheetSyncStatus.create_type()

    alter table(:sheets) do
      add :sync_status, Glific.Enums.SheetSyncStatus.type(),
        comment: "Status of the sync operation"

      add :failure_reason, :text
    end
  end
end
