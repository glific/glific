defmodule Glific.Repo.Migrations.AddRecordedAtIndexToVersions do
  use Ecto.Migration

  # Concurrent index build cannot run inside a transaction or hold the
  # Ecto migration advisory lock — required for a zero-downtime build on
  # the large production versions table.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists index(:versions, [:recorded_at],
                           concurrently: true,
                           comment:
                             "Lets the retention purge find expired rows without a seq scan (glific#5594)"
                         )
  end
end
