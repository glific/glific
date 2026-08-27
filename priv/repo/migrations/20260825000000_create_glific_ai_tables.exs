defmodule Glific.Repo.Migrations.CreateGlificAiTables do
  @moduledoc """
  Storage for Glific AI.

  Three levels, from outermost in:

    * `glific_ai_conversations` — a thread, owned by one user in one organization
    * `glific_ai_messages`      — one question and every step taken to answer it
    * `glific_ai_events`        — each individual step, in order

  There is deliberately no checkpoint table: the event log is the resumable state.
  Reload a message's events in `step` order, rebuild the model context, continue.

  Only what the read-only stage actually needs is here. Three things that earlier
  designs included are deliberately absent, each a small migration when its feature
  arrives:

    * the approval path — a proposal will become an event of type `suggestion`
      carrying its own status. Note that re-adding an enum value needs
      `ALTER TYPE ... ADD VALUE`, which cannot run inside a transaction, so that
      migration needs `@disable_ddl_transaction true`.
    * composition — `parent_message_id` and a depth cap, once a skill can invoke
      another skill.
    * a thread list — a title, an archived state and a last-event timestamp, once
      there is an interface that lists conversations.
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
      add :skill, :string,
        comment: "Which skill the router selected. Null until routing completes."

      add :status, :glific_ai_message_status_enum,
        null: false,
        default: "pending",
        comment:
          "Read-only for now, so there are no waiting states. The approval path adds awaiting_input and awaiting_approval."

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
        comment:
          "Who asked. An Oban worker has no GraphQL layer to authorize against, so the tool wrapper checks this user's role before every read."

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Organization scope"

      timestamps(type: :utc_datetime)
    end

    create index(:glific_ai_messages, [:organization_id])
    create index(:glific_ai_messages, [:organization_id, :conversation_id])

    create index(:glific_ai_messages, [:organization_id, :status],
             where: "status IN ('pending', 'running')",
             name: :glific_ai_messages_in_flight_index,
             comment: "Finds work that is still open without scanning finished messages"
           )
  end

  defp create_events do
    create table(:glific_ai_events,
             comment:
               "Every step taken while answering a question, in order. Append-only: this log is the resumable state, so rows are never rewritten."
           ) do
      add :step, :integer,
        null: false,
        comment:
          "Which step of its own message this is, numbering from 1. It restarts for each message, so conversation order is (message_id, step) and not step alone. Explicit rather than derived from inserted_at so that a retried job cannot write the same step twice."

      add :type, :glific_ai_event_type_enum,
        null: false,
        comment:
          "tool_result is kept distinct from assistant on purpose: it is untrusted content, and the type is what lets the loader frame it as data rather than instruction when rebuilding the context."

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

    create index(:glific_ai_events, [:message_id, :tool_call_id],
             where: "tool_call_id IS NOT NULL",
             name: :glific_ai_events_tool_call_index,
             comment: "Pairs calls to their results during replay"
           )
  end
end
