defmodule Glific.Repo.Migrations.AddGlificAISkills do
  use Ecto.Migration

  @moduledoc """
  Lets Glific AI route a request to a skill, and run one skill on its own.

  Three things: which skill handled a request, a record of the routing decision
  when a model made it, and whether a thread is a chat someone typed or a single
  skill run.
  """

  def up do
    alter table(:glific_ai_messages) do
      add :skill, :string,
        comment:
          "Which skill answered this request, whether chosen by intent or asked for directly"
    end

    execute("ALTER TYPE public.glific_ai_event_type_enum ADD VALUE IF NOT EXISTS 'routing';")

    execute("""
    CREATE TYPE public.glific_ai_conversation_kind_enum AS ENUM (
      'chat',
      'skill_run'
    );
    """)

    alter table(:glific_ai_conversations) do
      add :kind, :glific_ai_conversation_kind_enum,
        null: false,
        default: "chat",
        comment: "Whether this thread is a chat the person typed, or a single skill run"
    end
  end

  def down do
    alter table(:glific_ai_conversations) do
      remove :kind
    end

    execute("DROP TYPE IF EXISTS public.glific_ai_conversation_kind_enum;")

    alter table(:glific_ai_messages) do
      remove :skill
    end

    # Postgres cannot remove a value from an enum type, so 'routing' stays.
  end
end
