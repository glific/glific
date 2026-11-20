defmodule Glific.Repo.Migrations.AddIndexOnWhatsappKeyIdInWaMessages do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:wa_messages, [:whatsapp_key_id, :organization_id],
             name: "wa_messages_whatsapp_key_id_organization_id_index",
             where: "whatsapp_key_id IS NOT NULL",
             concurrently: true
           )
  end
end
