defmodule Glific.Repo.Migrations.AddSemanticVersioningToAssistantConfigVersions do
  use Ecto.Migration

  def up do
    execute(
      "CREATE TYPE public.assistant_config_version_bump_type_enum AS ENUM ('minor', 'major');"
    )

    rename table(:assistant_config_versions), :version_number, to: :major_version

    alter table(:assistant_config_versions) do
      add :minor_version, :integer,
        null: false,
        default: 0,
        comment: "Minor version number (bumped on every save)"

      add :bump_type, :assistant_config_version_bump_type_enum,
        null: false,
        default: "major",
        comment: "Whether this insert should bump the major or minor version"
    end

    execute(
      "ALTER TABLE assistant_config_versions ALTER COLUMN bump_type SET DEFAULT 'minor';"
    )

    execute("""
    COMMENT ON COLUMN assistant_config_versions.major_version
    IS 'Major version number (bumped on publish)';
    """)

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
  end

  def down do
    execute("""
    UPDATE assistant_config_versions acv
    SET major_version = ranked.row_number
    FROM (
      SELECT id, ROW_NUMBER() OVER (
        PARTITION BY assistant_id ORDER BY major_version, minor_version
      ) AS row_number
      FROM assistant_config_versions
    ) AS ranked
    WHERE acv.id = ranked.id;
    """)

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

    drop_if_exists unique_index(:assistant_config_versions, [
                     :assistant_id,
                     :major_version,
                     :minor_version
                   ])

    alter table(:assistant_config_versions) do
      remove :bump_type
      remove :minor_version
    end

    rename table(:assistant_config_versions), :major_version, to: :version_number

    alter table(:assistant_config_versions) do
      modify :version_number, :integer, null: false
    end

    execute("""
    COMMENT ON COLUMN assistant_config_versions.version_number
    IS 'Monotonically increasing config version per assistant';
    """)

    create unique_index(:assistant_config_versions, [:assistant_id, :version_number])

    execute("""
    CREATE TRIGGER assistant_convfig_version_set_version_number
    BEFORE INSERT ON assistant_config_versions
    FOR EACH ROW
    WHEN (NEW.version_number IS NULL)
    EXECUTE FUNCTION set_assistant_config_version_number();
    """)

    execute("DROP TYPE IF EXISTS public.assistant_config_version_bump_type_enum;")
  end
end
