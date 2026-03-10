defmodule Glific.Repo.Migrations.AddDeletedAtToOrganizations do
  use Ecto.Migration

  def up do
    alter table(:organizations) do
      add(:deleted_at, :utc_datetime, null: true)
    end

    # Partial index for fast filtering of non-deleted organizations
    create index(:organizations, [:deleted_at],
             where: "deleted_at IS NULL",
             name: :organizations_deleted_index
           )

    create_delete_organization_data_function()
  end

  def down do
    execute("DROP FUNCTION IF EXISTS delete_organization_data(BIGINT)")

    drop_if_exists index(:organizations, [:deleted_at], name: :organizations_deleted_index)

    alter table(:organizations) do
      remove(:deleted_at)
    end
  end

  # Creates a PostgreSQL function that dynamically discovers and deletes all
  # organization data from every table with an organization_id column.
  # This ensures any new tables added in the future are automatically covered.
  defp create_delete_organization_data_function do
    execute("""
    CREATE OR REPLACE FUNCTION delete_organization_data(org_id BIGINT)
    RETURNS void AS $$
    DECLARE
      tbl TEXT;
      rows_deleted BIGINT;
    BEGIN
      -- Guard: refuse to erase data for an org that has not been soft-deleted yet.
      IF NOT EXISTS (
        SELECT 1 FROM organizations WHERE id = org_id AND deleted_at IS NOT NULL
      ) THEN
        RAISE EXCEPTION 'Organization % has not been soft-deleted. Call delete_organization first.', org_id;
      END IF;

      -- Disable FK triggers temporarily so alphabetical deletion order does not
      -- cause RESTRICT violations between org-scoped tables (e.g. whatsapp_forms
      -- references whatsapp_form_revisions). Re-enabled after the loop.
      SET session_replication_role = 'replica';

      BEGIN
        -- Null out nullable foreign keys on the organization row to avoid FK violations.
        -- bsp_id and default_language_id are NOT NULL so they cannot be nullified here;
        -- they reference global tables (providers, languages) that are never deleted anyway.
        UPDATE organizations
        SET contact_id = NULL, newcontact_flow_id = NULL, optin_flow_id = NULL
        WHERE id = org_id;

        -- Dynamically delete from all tables with organization_id column
        FOR tbl IN
          SELECT table_name
          FROM information_schema.columns
          WHERE column_name = 'organization_id'
            AND table_schema = 'public'
            AND table_name != 'organizations'
          ORDER BY table_name
        LOOP
          EXECUTE format('DELETE FROM %I WHERE organization_id = %s', tbl, org_id);
          GET DIAGNOSTICS rows_deleted = ROW_COUNT;
          IF rows_deleted > 0 THEN
            RAISE NOTICE 'Deleted % rows from %', rows_deleted, tbl;
          END IF;
        END LOOP;

        SET session_replication_role = 'origin';
      EXCEPTION WHEN OTHERS THEN
        SET session_replication_role = 'origin';
        RAISE;
      END;
    END;
    $$ LANGUAGE plpgsql;
    """)
  end
end
