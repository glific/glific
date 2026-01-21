defmodule Glific.Repo.Migrations.CreateUnifiedApiVersioningTables do
  use Ecto.Migration

  def up do
    create_enums()
    create_assistants()
    create_assistant_config_versions()
    create_knowledge_bases()
    create_knowledge_base_versions()
    create_assistant_config_version_knowledge_base_versions()
    create_triggers()
  end

  def down do
    drop_triggers()
    drop_if_exists(table(:assistant_config_version_knowledge_base_versions))

    drop_if_exists(table(:knowledge_base_versions))
    drop_if_exists(table(:knowledge_bases))
    drop_if_exists(table(:assistant_config_versions))
    drop_if_exists(table(:assistants))
    drop_enums()
  end

  defp create_enums do
    execute("""
    CREATE TYPE public.assistant_config_version_status_enum AS ENUM (
      'in_progress',
      'ready',
      'failed'
    );
    """)

    execute("""
    CREATE TYPE public.knowledge_base_status_enum AS ENUM (
      'in_progress',
      'completed',
      'failed'
    );
    """)
  end

  defp drop_enums do
    execute("DROP TYPE IF EXISTS public.knowledge_base_status_enum;")
    execute("DROP TYPE IF EXISTS public.assistant_config_version_status_enum;")
  end

  defp create_assistants do
    create table(:assistants) do
      add :name, :string, null: false, comment: "Name of the assistant"
      add :description, :text, comment: "Description of the assistant"

      add :active_config_version_id,
          references(:assistant_config_versions, on_delete: :nilify_all),
          null: true,
          comment: "Currently active assistant config version"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      timestamps(type: :utc_datetime)
    end

    create index(:assistants, [:organization_id])
  end

  defp create_assistant_config_versions do
    create table(:assistant_config_versions) do
      add :version_number, :integer,
        null: false,
        comment: "Monotonically increasing config version per assistant"

      add :description, :text, comment: "Description for this version"
      add :prompt, :text, null: false, comment: "Prompt/instructions for this version"
      add :kaapi_uuid, :string, null: false, comment: "Kaapi UUID for the config"

      add :provider, :string,
        null: false,
        default: "openai",
        comment: "LLM provider for this version"

      add :model, :string, null: false, comment: "Model used by this version"

      add :settings, :jsonb,
        default: "{}",
        comment: "Provider-specific settings like temperature, etc."

      add :status, :assistant_config_version_status_enum,
        null: false,
        default: "in_progress",
        comment: "Status of this version - in_progress, ready, failed"

      add :failure_reason, :text, comment: "Failure reason if status is failed"
      add :deleted_at, :utc_datetime, comment: "Soft-delete timestamp"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      add :assistant_id, references(:assistants, on_delete: :delete_all),
        null: false,
        comment: "Assistant this configuration belongs to"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:assistant_config_versions, [:assistant_id, :version_number])
    create index(:assistant_config_versions, [:assistant_id])
    create index(:assistant_config_versions, [:organization_id])
  end

  defp create_knowledge_bases do
    create table(:knowledge_bases) do
      add :name, :string, null: false, comment: "Name of the knowledge base"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      timestamps(type: :utc_datetime)
    end

    create index(:knowledge_bases, [:organization_id])
  end

  defp create_knowledge_base_versions do
    create table(:knowledge_base_versions) do
      add :version_number, :integer,
        null: false,
        comment: "Monotonically increasing version per knowledge base"

      add :llm_service_id, :string,
        comment: "Provider-side vector store identifier (if available)"

      add :kaapi_job_id, :string,
        comment: "Async job id returned by Kaapi during knowledge base creation"

      add :files, :jsonb, default: "{}", comment: "Files metadata for this knowledge base version"
      add :size, :bigint, default: 0, comment: "Size of this knowledge base version"

      add :status, :knowledge_base_status_enum,
        null: false,
        default: "in_progress",
        comment: "Status of knowledge base creation - in_progress, completed, failed"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      add :knowledge_base_id, references(:knowledge_bases, on_delete: :delete_all),
        null: false,
        comment: "Knowledge base this version belongs to"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:knowledge_base_versions, [:knowledge_base_id, :version_number])
    create index(:knowledge_base_versions, [:knowledge_base_id])
    create index(:knowledge_base_versions, [:organization_id])
    create index(:knowledge_base_versions, [:status])
  end

  defp create_assistant_config_version_knowledge_base_versions do
    create table(:assistant_config_version_knowledge_base_versions) do
      add :assistant_config_version_id,
          references(:assistant_config_versions, on_delete: :delete_all),
          null: false,
          comment: "Assistant config version id"

      add :knowledge_base_version_id,
          references(:knowledge_base_versions, on_delete: :delete_all),
          null: false,
          comment: "Knowledge base version id"

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      timestamps(type: :utc_datetime)
    end

    create index(:assistant_config_version_knowledge_base_versions, [:assistant_config_version_id])

    create index(:assistant_config_version_knowledge_base_versions, [:knowledge_base_version_id])
    create index(:assistant_config_version_knowledge_base_versions, [:organization_id])
  end

  defp create_triggers do
    create_assistant_config_version_triggers()
    create_knowledge_base_version_triggers()
  end

  defp create_assistant_config_version_triggers do
    execute("""
    CREATE OR REPLACE FUNCTION set_assistant_config_version_number()
    RETURNS trigger AS $$
    BEGIN
      SELECT COALESCE(MAX(version_number), 0) + 1
      INTO NEW.version_number
      FROM assistant_config_versions
      WHERE assistant_id = NEW.assistant_id
      FOR UPDATE;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER assistant_convfig_version_set_version_number
    BEFORE INSERT ON assistant_config_versions
    FOR EACH ROW
    WHEN (NEW.version_number IS NULL)
    EXECUTE FUNCTION set_assistant_config_version_number();
    """)
  end

  defp create_knowledge_base_version_triggers do
    execute("""
    CREATE OR REPLACE FUNCTION set_knowledge_base_version_number()
    RETURNS trigger AS $$
    BEGIN
      SELECT COALESCE(MAX(version_number), 0) + 1
      INTO NEW.version_number
      FROM knowledge_base_versions
      WHERE knowledge_base_id = NEW.knowledge_base_id
      FOR UPDATE;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER knowledge_base_version_set_version_number
    BEFORE INSERT ON knowledge_base_versions
    FOR EACH ROW
    WHEN (NEW.version_number IS NULL)
    EXECUTE FUNCTION set_knowledge_base_version_number();
    """)
  end

  defp drop_triggers do
    execute(
      "DROP TRIGGER IF EXISTS assistant_convfig_version_set_version_number ON assistant_config_versions;"
    )

    execute("DROP FUNCTION IF EXISTS set_assistant_config_version_number();")

    execute(
      "DROP TRIGGER IF EXISTS knowledge_base_version_set_version_number ON knowledge_base_versions;"
    )

    execute("DROP FUNCTION IF EXISTS set_knowledge_base_version_number();")
  end
end
