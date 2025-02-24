defmodule Glific.Repo.Migrations.PendingIndexes do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:wa_messages, :contact_id, name: "wa_messages_contact_id_index")
    create_if_not_exists index(:wa_messages, :media_id, name: "wa_messages_media_id_index")
    drop_if_exists index(:webhook_logs, :contact_id)

    create_if_not_exists index(:webhook_logs, :contact_id,
                           name: "webhook_logs_contact_id_index",
                           where: "contact_id IS NOT NULL"
                         )

    create_if_not_exists index(:webhook_logs, :wa_group_id,
                           name: "webhook_logs_wa_group_id_index",
                           where: "wa_group_id IS NOT NULL"
                         )

    create_if_not_exists index(:messages_media, :inserted_at,
                           name: "messages_media_inserted_at_index"
                         )
  end
end
