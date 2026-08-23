defmodule Glific.Repo.Migrations.CreateAiMessages do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TYPE public.ai_message_role_enum AS ENUM (
      'user',
      'assistant',
      'tool'
    );
    """)

    execute("""
    CREATE TYPE public.ai_message_status_enum AS ENUM (
      'complete',
      'failed'
    );
    """)

    create table(:ai_messages) do
      add :conversation_id, references(:ai_conversations, on_delete: :delete_all),
        null: false,
        comment: "Conversation this message belongs to"

      add :seq, :integer,
        null: false,
        comment: "Position within the conversation; the retry-safe insert key"

      add :role, :ai_message_role_enum, null: false, comment: "user | assistant | tool"

      add :parts, :jsonb,
        null: false,
        default: "{}",
        comment: "Glific.AI.Codec-encoded ReqLLM.Message"

      add :status, :ai_message_status_enum,
        null: false,
        default: "complete",
        comment: "complete | failed; failed rows are excluded when rebuilding context"

      add :request_id, :string, comment: "Groups every row produced by one user turn"
      add :model, :string, comment: "Model that produced this message, if applicable"
      add :prompt_tokens, :integer, null: false, default: 0
      add :completion_tokens, :integer, null: false, default: 0
      add :cached_tokens, :integer, null: false, default: 0
      add :duration_ms, :integer, comment: "Wall-clock time to produce this message"
      add :error, :text, comment: "Failure detail when status is failed"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization scope"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_messages, [:conversation_id, :seq])
    create index(:ai_messages, [:organization_id, :inserted_at])
    create index(:ai_messages, [:request_id])
  end

  def down do
    drop table(:ai_messages)
    execute("DROP TYPE IF EXISTS public.ai_message_status_enum;")
    execute("DROP TYPE IF EXISTS public.ai_message_role_enum;")
  end
end
