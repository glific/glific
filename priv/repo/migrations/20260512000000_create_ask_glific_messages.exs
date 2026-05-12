defmodule Glific.Repo.Migrations.CreateAskGlificMessages do
  use Ecto.Migration

  def change do
    create table(:ask_glific_messages) do
      add :dify_message_id, :string
      add :conversation_id, :string
      add :question, :text, null: false
      add :answer, :text
      add :latency_ms, :integer
      add :status, :string, null: false
      add :error_reason, :text
      add :rating, :string
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:ask_glific_messages, [:organization_id])
    create index(:ask_glific_messages, [:user_id])
    create index(:ask_glific_messages, [:conversation_id])
    create index(:ask_glific_messages, [:dify_message_id])
  end
end
