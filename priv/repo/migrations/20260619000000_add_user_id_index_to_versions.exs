defmodule Glific.Repo.Migrations.AddUserIdIndexToVersions do
  use Ecto.Migration

  # Concurrent index build cannot run inside a transaction or hold the
  # Ecto migration advisory lock — required for a zero-downtime build on
  # the large production versions table.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:versions, [:user_id],
             concurrently: true,
             comment: "Speeds up FK nilify_all on user deletion (glific#5188)"
           )
  end
end
