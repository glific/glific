defmodule Glific.Repo.Migrations.CreateAskmeBotConversations do
  use Ecto.Migration

  def change do
    create table(:askme_bot_conversations) do
      add :conversation_id, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:askme_bot_conversations, [:user_id, :conversation_id])
    create index(:askme_bot_conversations, [:organization_id])
  end
end
