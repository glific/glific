defmodule Glific.Repo.Migrations.ChangeDefaultValueOfSheetSyncStatus do
  use Ecto.Migration

  def change do
    execute "UPDATE sheets SET sync_status = 'success' WHERE sync_status != 'failed';"

    alter table(:sheets) do
      modify :sync_status, Glific.Enums.SheetSyncStatus.type(), default: "success"
    end
  end
end
