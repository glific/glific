defmodule Glific.Repo.Migrations.CreateGlificAiTables do
  @moduledoc """
  Storage for Glific AI.

  Three levels, from outermost in:

    * `glific_ai_conversations` — a thread, owned by one user in one organization
    * `glific_ai_messages`      — one question and every step taken to answer it
    * `glific_ai_events`        — each individual step, in order

  Reloading a conversation's events in `step` order rebuilds the context sent to
  the model, which is how a follow-up question keeps what came before.
  """

  use Ecto.Migration

  def up do
    create_enums()
    create_conversations()
    create_messages()
    create_events()
  end

  def down do
    drop_if_exists(table(:glific_ai_events))
    drop_if_exists(table(:glific_ai_messages))
    drop_if_exists(table(:glific_ai_conversations))
    drop_enums()
  end

  defp create_enums do
    execute("""
    CREATE TYPE public.glific_ai_message_status_enum AS ENUM (
      'pending',
      'running',
      'succeeded',
      'failed',
      'cancelled'
    );
    """)

    execute("""
    CREATE TYPE public.glific_ai_event_type_enum AS ENUM (
      'user',
      'assistant',
      'tool_call',
      'tool_result'
    );
    """)
  end

  defp drop_enums do
    execute("DROP TYPE IF EXISTS public.glific_ai_event_type_enum;")
    execute("DROP TYPE IF EXISTS public.glific_ai_message_status_enum;")
  end

  defp create_conversations do
    create table(:glific_ai_conversations,
             comment: "A Glific AI chat thread, owned by one user within one organization"
           ) do
      add :title, :string,
        comment: "Short label derived from the first question. Null until the first answer."

      add :user_id, references(:users, on_delete: :delete_all),
        null: false,
        comment: "The staff member who owns this thread"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization scope"

      timestamps(type: :utc_datetime)
    end

    create index(:glific_ai_conversations, [:organization_id])
    create index(:glific_ai_conversations, [:organization_id, :user_id])
  end

  defp create_messages do
    create table(:glific_ai_messages,
             comment:
               "One question and every step taken to answer it. Carries the lifecycle, the cost, and the composition tree."
           ) do
      add :status, :glific_ai_message_status_enum,
        null: false,
        default: "pending",
        comment: "Glific AI only reads data at this stage, so a message either finishes or fails."

      add :error, :text, comment: "Why it failed, when status is failed"

      add :model, :string, comment: "Model that served this message, e.g. anthropic:claude-opus-5"

      add :input_tokens, :integer,
        null: false,
        default: 0,
        comment: "Summed across every model call made answering this one question"

      add :output_tokens, :integer, null: false, default: 0

      add :cost, :decimal,
        precision: 12,
        scale: 6,
        null: false,
        default: 0,
        comment: "Estimated USD, summed across every model call. Observability, not an invoice."

      add :conversation_id, references(:glific_ai_conversations, on_delete: :delete_all),
        null: false,
        comment: "The thread this belongs to"

      add :user_id, references(:users, on_delete: :delete_all),
        null: false,
        comment: "Who asked. Reads made while answering are scoped to this user's permissions."

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization scope"

      timestamps(type: :utc_datetime)
    end

    create index(:glific_ai_messages, [:organization_id])
  end

  defp create_events do
    create table(:glific_ai_events,
             comment:
               "Every step taken while answering a question, in order. Append-only: rows are never rewritten."
           ) do
      add :step, :integer,
        null: false,
        comment:
          "Which step of its own message this is, from 1. It restarts for each message, so conversation order is (message_id, step). Unique per message, so a retried job cannot write the same step twice."

      add :type, :glific_ai_event_type_enum,
        null: false,
        comment:
          "tool_result is separate from assistant because tool output is data about the account, never instructions to the model."

      add :content, :text,
        comment: "The human-readable part. Reading down this column reads the conversation."

      add :data, :map,
        null: false,
        default: %{},
        comment:
          "The structured part: tool arguments and tool output. Kept out of content so the table stays readable."

      add :tool_call_id, :string,
        comment:
          "Pairs a tool_call with its tool_result. Required to rebuild the context faithfully on replay."

      add :message_id, references(:glific_ai_messages, on_delete: :delete_all),
        null: false,
        comment: "The question this step was taken in service of"

      add :conversation_id, references(:glific_ai_conversations, on_delete: :delete_all),
        null: false,
        comment:
          "Denormalized from the message so a whole thread loads in one query, with no join"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization scope"

      timestamps(type: :utc_datetime)
    end

    # Scoped to the message, not the conversation: two messages in one thread run
    # concurrently, and conversation-wide numbering would make them race for the same
    # value. This also stops an Oban retry writing a step twice.
    create unique_index(:glific_ai_events, [:message_id, :step])

    create index(:glific_ai_events, [:organization_id])
    create index(:glific_ai_events, [:organization_id, :conversation_id])
  end
end
