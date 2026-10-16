defmodule Glific.Repo.Migrations.AddOrganizationIdUpdatedAtIndexToMessagesMedia do
  use Ecto.Migration

  # Concurrent index build cannot run inside a transaction or hold the
  # Ecto migration advisory lock — required for a zero-downtime build on
  # the large production messages_media table.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Production gets this index by hand ahead of the deploy, so it must be a no-op there.
    create_if_not_exists index(:messages_media, [:organization_id, :updated_at],
                           concurrently: true,
                           comment:
                             "Lets the BigQuery update sync find an org's changed rows without walking every org's updated_at range"
                         )
  end
end
