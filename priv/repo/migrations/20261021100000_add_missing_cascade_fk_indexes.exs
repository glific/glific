defmodule Glific.Repo.Migrations.AddMissingCascadeFkIndexes do
  use Ecto.Migration

  # Without these, every ON DELETE CASCADE from contacts / wa_messages runs a sequential
  # scan of the child table, which makes org data erase time out on large tables.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create_if_not_exists index(:tickets, [:contact_id], concurrently: true)
    create_if_not_exists index(:contacts_wa_groups, [:contact_id], concurrently: true)
    create_if_not_exists index(:wa_messages, [:context_message_id], concurrently: true)
  end

  def down do
    drop_if_exists index(:tickets, [:contact_id], concurrently: true)
    drop_if_exists index(:contacts_wa_groups, [:contact_id], concurrently: true)
    drop_if_exists index(:wa_messages, [:context_message_id], concurrently: true)
  end
end
