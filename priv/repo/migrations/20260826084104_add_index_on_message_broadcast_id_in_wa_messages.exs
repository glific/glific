defmodule Glific.Repo.Migrations.AddIndexOnMessageBroadcastIdInWaMessages do
  use Ecto.Migration

  def change do
    create index(:wa_messages, [:message_broadcast_id],
             name: "wa_messages_message_broadcast_id_index",
             where: "message_broadcast_id IS NOT NULL"
           )
  end
end
