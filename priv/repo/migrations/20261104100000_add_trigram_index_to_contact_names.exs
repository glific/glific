defmodule Glific.Repo.Migrations.AddTrigramIndexToContactNames do
  use Ecto.Migration

  # Concurrent index builds cannot run inside a transaction or hold the Ecto
  # migration advisory lock — required on the large production contacts table.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Contact search matches a name anywhere (`name ILIKE '%term%'`), which a B-tree index cannot
    # serve, so every search read every contact in the organization. A trigram index serves it
    # for terms of three or more characters. pg_trgm is already enabled (structure.sql), and
    # messages already has trigram indexes on body and flow_label.
    #
    # `create`, not `create_if_not_exists`: an interrupted concurrent build leaves an invalid index
    # with this name, which IF NOT EXISTS would skip. Drop it (DROP INDEX CONCURRENTLY
    # contacts_name_trgm_index) before retrying.
    create index(:contacts, ["name gin_trgm_ops"],
             name: :contacts_name_trgm_index,
             using: "GIN",
             concurrently: true,
             comment: "Backs contact search matching a name anywhere"
           )
  end

  def down do
    drop_if_exists index(:contacts, ["name gin_trgm_ops"],
                     name: :contacts_name_trgm_index,
                     concurrently: true
                   )
  end
end
