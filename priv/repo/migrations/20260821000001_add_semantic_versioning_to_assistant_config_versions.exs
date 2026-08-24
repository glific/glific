defmodule Glific.Repo.Migrations.AddSemanticVersioningToAssistantConfigVersions do
  use Ecto.Migration

  def up do
    execute(
      "CREATE TYPE public.assistant_config_version_bump_type_enum AS ENUM ('minor', 'major');"
    )

    alter table(:assistant_config_versions) do
      add :major_version, :integer, comment: "Major version number (bumped on publish)"
      add :minor_version, :integer, comment: "Minor version number (bumped on every save)"

      add :bump_type, :assistant_config_version_bump_type_enum,
        null: false,
        default: "minor",
        comment: "Whether this insert should bump the major or minor version"
    end

    execute(
      "UPDATE assistant_config_versions SET major_version = 1, minor_version = version_number - 1"
    )

    alter table(:assistant_config_versions) do
      modify :major_version, :integer, null: false
      modify :minor_version, :integer, null: false
    end

    drop_if_exists unique_index(:assistant_config_versions, [:assistant_id, :version_number])

    create unique_index(:assistant_config_versions, [
             :assistant_id,
             :major_version,
             :minor_version
           ])

    execute("""
    CREATE OR REPLACE FUNCTION set_assistant_config_version_number()
    RETURNS trigger AS $$
    BEGIN
      PERFORM id FROM assistants WHERE id = NEW.assistant_id FOR UPDATE;

      IF NEW.bump_type = 'major' THEN
        SELECT COALESCE(MAX(major_version), 0) + 1
        INTO NEW.major_version
        FROM assistant_config_versions
        WHERE assistant_id = NEW.assistant_id;

        NEW.minor_version := 0;
      ELSE
        SELECT major_version, minor_version
        INTO NEW.major_version, NEW.minor_version
        FROM assistant_config_versions
        WHERE assistant_id = NEW.assistant_id
        ORDER BY major_version DESC, minor_version DESC
        LIMIT 1;

        IF NEW.major_version IS NULL THEN
          NEW.major_version := 1;
          NEW.minor_version := 0;
        ELSE
          NEW.minor_version := NEW.minor_version + 1;
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute(
      "DROP TRIGGER IF EXISTS assistant_convfig_version_set_version_number ON assistant_config_versions;"
    )

    execute("""
    CREATE TRIGGER assistant_config_version_set_version_number
    BEFORE INSERT ON assistant_config_versions
    FOR EACH ROW
    WHEN (NEW.major_version IS NULL OR NEW.minor_version IS NULL)
    EXECUTE FUNCTION set_assistant_config_version_number();
    """)

    alter table(:assistant_config_versions) do
      remove :version_number
    end
  end

  def down do
    alter table(:assistant_config_versions) do
      add :version_number, :integer,
        comment: "Monotonically increasing config version per assistant"
    end

    execute("""
    UPDATE assistant_config_versions acv
    SET version_number = ranked.row_number
    FROM (
      SELECT id, ROW_NUMBER() OVER (
        PARTITION BY assistant_id ORDER BY major_version, minor_version
      ) AS row_number
      FROM assistant_config_versions
    ) AS ranked
    WHERE acv.id = ranked.id;
    """)

    alter table(:assistant_config_versions) do
      modify :version_number, :integer, null: false
    end

    execute(
      "DROP TRIGGER IF EXISTS assistant_config_version_set_version_number ON assistant_config_versions;"
    )

    execute("DROP FUNCTION IF EXISTS set_assistant_config_version_number();")

    execute("""
    CREATE OR REPLACE FUNCTION set_assistant_config_version_number()
    RETURNS trigger AS $$
    BEGIN
      PERFORM id FROM assistants WHERE id = NEW.assistant_id FOR UPDATE;

      SELECT COALESCE(MAX(version_number), 0) + 1
      INTO NEW.version_number
      FROM assistant_config_versions
      WHERE assistant_id = NEW.assistant_id;

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

    drop_if_exists unique_index(:assistant_config_versions, [
                     :assistant_id,
                     :major_version,
                     :minor_version
                   ])

    create unique_index(:assistant_config_versions, [:assistant_id, :version_number])

    alter table(:assistant_config_versions) do
      remove :bump_type
      remove :minor_version
      remove :major_version
    end

    execute("DROP TYPE IF EXISTS public.assistant_config_version_bump_type_enum;")
  end
end
