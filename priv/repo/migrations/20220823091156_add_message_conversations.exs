defmodule Glific.Repo.Migrations.AddMessageConversations do
  use Ecto.Migration

  def change do
    create_messages_conversations()
  end

  defp create_messages_conversations() do
    create table(:messages_conversations) do
      add :conversation_id, :string
      add :deduction_type, :string
      add :is_billable, :boolean, default: false, null: false

      add :message_id, references(:messages, on_delete: :delete_all),
        null: false,
        comment: "reference for the message"

      add :contact_id, references(:contacts, on_delete: :delete_all),
        null: false,
        comment: "reference for the contact"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "reference for the organization"

      add :payload, :jsonb, default: "{}"
      timestamps(type: :utc_datetime)
    end

    create index(:messages_conversations, :contact_id)
    create index(:messages_conversations, :message_id)
    create index(:messages_conversations, :organization_id)
  end
end
