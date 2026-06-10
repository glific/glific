defmodule Glific.Repo.Migrations.FixDeleteOrganizationDataPermissions do
  use Ecto.Migration

  @moduledoc """
  Replaces the delete_organization_data function to add SECURITY DEFINER so it
  executes with the privileges of the role that created it (the migration/DB-owner
  role), rather than the calling role.

  The function uses `SET session_replication_role = 'replica'` to bypass FK triggers
  during bulk deletion, which requires superuser privilege. The application DB user
  does not have superuser on production (Gigalixir), causing an insufficient_privilege
  error. With SECURITY DEFINER the function inherits the DB owner's privileges, which
  include the ability to set session_replication_role.
  """

  def up do
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
      -- cause RESTRICT violations between org-scoped tables.
      -- SECURITY DEFINER ensures this runs with DB-owner privileges on production.
      SET session_replication_role = 'replica';

      BEGIN
        -- Null out nullable foreign keys on the organization row to avoid FK violations.
        -- bsp_id and default_language_id are NOT NULL so they cannot be nullified here;
        -- they reference global tables (providers, languages) that are never deleted anyway.
        UPDATE organizations
        SET contact_id = NULL, newcontact_flow_id = NULL, optin_flow_id = NULL
        WHERE id = org_id;

        -- Dynamically delete from all tables with organization_id column in alphabetical order.
        FOR tbl IN
          SELECT DISTINCT cls.relname::text AS table_nm
          FROM pg_attribute att
          JOIN pg_class cls ON att.attrelid = cls.oid
          JOIN pg_namespace ns ON cls.relnamespace = ns.oid
          WHERE att.attname = 'organization_id'
            AND ns.nspname = 'public'
            AND cls.relkind = 'r'
            AND cls.relname != 'organizations'
            AND NOT att.attisdropped
          ORDER BY table_nm
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
    $$ LANGUAGE plpgsql SECURITY DEFINER;
    """)
  end

  def down do
    execute("""
    CREATE OR REPLACE FUNCTION delete_organization_data(org_id BIGINT)
    RETURNS void AS $$
    DECLARE
      tbl TEXT;
      rows_deleted BIGINT;
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM organizations WHERE id = org_id AND deleted_at IS NOT NULL
      ) THEN
        RAISE EXCEPTION 'Organization % has not been soft-deleted. Call delete_organization first.', org_id;
      END IF;

      SET session_replication_role = 'replica';

      BEGIN
        UPDATE organizations
        SET contact_id = NULL, newcontact_flow_id = NULL, optin_flow_id = NULL
        WHERE id = org_id;

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
    $$ LANGUAGE plpgsql SECURITY DEFINER;
    """)
  end
end
