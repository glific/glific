defmodule Glific.Repo.Migrations.AddIndexOnMessageBroadcastIdInWaMessages do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:wa_messages, [:message_broadcast_id],
             name: "wa_messages_message_broadcast_id_index",
             where: "message_broadcast_id IS NOT NULL",
             concurrently: true
           )
  end
end
