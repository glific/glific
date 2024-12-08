defmodule Glific.Repo.Migrations.CreateWaReactionsTable do
  use Ecto.Migration

  def change do
    create table(:wa_reactions) do
      add :bsp_id, :string, null: false, comment: "Message ID from provider"

      add :reaction, :text, null: false, comment: "Reaction"

      add :wa_message_id, references(:wa_messages, on_delete: :delete_all),
        null: false,
        comment: "Unique WA Message ID"

      add :contact_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment: "Unique contact ID"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      timestamps(type: :utc_datetime)
    end

    create index(:wa_reactions, [:wa_message_id])
    create unique_index(:wa_reactions, [:wa_message_id, :contact_id])
  end
end
