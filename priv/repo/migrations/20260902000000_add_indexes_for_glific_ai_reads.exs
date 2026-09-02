defmodule Glific.Repo.Migrations.AddIndexesForGlificAIReads do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists index(
                           :message_broadcast_contacts,
                           [:message_broadcast_id, :processed_at, :id],
                           concurrently: true
                         )

    create_if_not_exists index(:wa_messages, [:wa_group_id, :inserted_at], concurrently: true)
  end
end
