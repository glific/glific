defmodule Glific.Repo.Migrations.CreateAiConversations do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TYPE public.ai_request_status_enum AS ENUM (
      'queued',
      'running',
      'awaiting_confirmation',
      'succeeded',
      'failed',
      'cancelled',
      'expired'
    );
    """)

    create table(:ai_conversations) do
      add :skill, :string, null: false, comment: "The agent skill driving this conversation"
      add :title, :string, comment: "Display title for the chat list"

      add :status, :string,
        null: false,
        default: "active",
        comment: "active | archived"

      add :active_request_id, :string,
        comment: "Correlation key for the in-flight turn; nil when idle"

      add :active_status, :ai_request_status_enum,
        comment: "queued | running | awaiting_confirmation while a turn is in flight, else null"

      add :step_count, :integer,
        null: false,
        default: 0,
        comment: "Steps taken in the current run"

      add :max_steps, :integer,
        null: false,
        comment: "Step budget snapshotted at run start, so a mid-run deploy cannot change it"

      add :gate_token, :string, comment: "Opaque token guarding a pending human confirmation"
      add :gate_expires_at, :utc_datetime, comment: "Expiry for gate_token"
      add :pending_proposal, :jsonb, comment: "Action awaiting human confirmation, if any"
      add :last_error, :jsonb, comment: "Structured detail of the most recent run failure"
      add :token_count, :integer, null: false, default: 0, comment: "Cumulative token usage"
      add :codec_version, :integer, null: false, comment: "Glific.AI.Codec version in effect"
      add :req_llm_version, :string, comment: "req_llm library version in effect"
      add :last_message_at, :utc_datetime, comment: "Timestamp of the most recent message"

      add :user_id, references(:users, on_delete: :delete_all),
        null: false,
        comment:
          "Creator of this conversation. delete_all: a conversation's messages can hold data " <>
            "no one else in the org may see, so there is no one left to retain it for once the " <>
            "user is gone, and :restrict would block ordinary user offboarding."

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization scope"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_conversations, [:active_request_id],
             where: "active_request_id IS NOT NULL"
           )

    create index(:ai_conversations, [:active_status], where: "active_status IS NOT NULL")
    create index(:ai_conversations, [:organization_id, :user_id, :updated_at])
    create index(:ai_conversations, [:organization_id])
  end

  def down do
    drop table(:ai_conversations)
    execute("DROP TYPE IF EXISTS public.ai_request_status_enum;")
  end
end
