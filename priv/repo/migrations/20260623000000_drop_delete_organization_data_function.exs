defmodule Glific.Repo.Migrations.DropDeleteOrganizationDataFunction do
  use Ecto.Migration

  # Organization data erasure now lives in Elixir (`Glific.Erase.delete_all_organization_data/1`),
  # which deletes each org-scoped table explicitly in topological FK order inside a single
  # transaction. The previous PL/pgSQL `delete_organization_data` function (added in
  # 20260219120000_add_deleted_at_to_organizations.exs) discovered tables dynamically and disabled
  # FK triggers via `SET session_replication_role = 'replica'`, which requires SUPERUSER privilege
  # the application DB user lacks on production (Gigalixir) — see issue #5165. The function is now
  # unused, so drop it.

  def up do
    execute("DROP FUNCTION IF EXISTS delete_organization_data(BIGINT)")
  end

  # Recreate the original dynamic function (verbatim from 20260219120000) so the migration is
  # reversible.
  def down do
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
