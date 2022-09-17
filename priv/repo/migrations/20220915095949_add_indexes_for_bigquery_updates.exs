defmodule Glific.Repo.Migrations.AddIndexesForBigqueryUpdates do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:contact_histories, :updated_at)
    create_if_not_exists index(:messages_media, :updated_at)
    create_if_not_exists index(:contacts, :updated_at)
    create_if_not_exists index(:contacts, :last_message_at)
    create_if_not_exists index(:contacts, :bsp_status)
    create_if_not_exists index(:contact_histories, :contact_id)
  end
end
