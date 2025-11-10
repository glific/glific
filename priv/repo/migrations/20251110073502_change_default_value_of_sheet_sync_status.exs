defmodule Glific.Repo.Migrations.ChangeDefaultValueOfSheetSyncStatus do
  use Ecto.Migration

  def change do
    alter table(:sheets) do
      modify :sync_status, Glific.Enums.SheetSyncStatus.type(), default: "success"
    end

    execute "UPDATE sheets SET sync_status = 'success' WHERE sync_status IS NULL OR sync_status = 'pending';"
  end
end
