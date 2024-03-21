defmodule Glific.Repo.Migrations.AddWaMessageInLocation do
  use Ecto.Migration

  def change do
    alter table(:locations) do
      add :wa_message_id, references(:wa_messages, on_delete: :delete_all),
        null: true,
        comment: "ID of WA group"
    end
  end
end
