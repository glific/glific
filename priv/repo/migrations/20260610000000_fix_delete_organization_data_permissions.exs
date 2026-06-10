defmodule Glific.Repo.Migrations.FixDeleteOrganizationDataPermissions do
  use Ecto.Migration

  @moduledoc """
  Replaces the delete_organization_data function to use topological sort with
  cycle-breaking instead of SET session_replication_role = 'replica'.

  The original function used session_replication_role to bypass FK checks during
  alphabetical bulk deletion. That requires superuser privilege, which the app DB
  user does not have on Gigalixir production.

  The new approach:
  1. Builds a FK dependency graph between all org-scoped tables using pg_catalog.
  2. Runs Kahn's topological sort so tables are deleted in FK-safe order.
  3. When a cycle is detected (e.g. contacts <-> profiles), breaks it by nulling
     the nullable FK column(s) for the org being deleted, then continues sorting.

  No elevated privileges required — works with the standard app DB user.
  """

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION delete_organization_data(org_id BIGINT)
    RETURNS void AS $$
    DECLARE
      v_tbl     TEXT;
      v_from    TEXT;
      v_cols    TEXT;
      v_con_oid OID;
      v_deleted BIGINT;
      v_progress BOOLEAN;
      v_ord     INT := 0;
    BEGIN
      -- Guard: refuse to erase data for an org that has not been soft-deleted yet.
      IF NOT EXISTS (
        SELECT 1 FROM organizations WHERE id = org_id AND deleted_at IS NOT NULL
      ) THEN
        RAISE EXCEPTION 'Organization % has not been soft-deleted. Call delete_organization first.', org_id;
      END IF;

      -- Null nullable self-references on the organization row so the tables they
      -- point to (contacts, flows) can be deleted without FK violations.
      UPDATE organizations
      SET contact_id = NULL, newcontact_flow_id = NULL, optin_flow_id = NULL
      WHERE id = org_id;

      -- Clean up any leftover temp tables from a prior invocation in the same transaction.
      DROP TABLE IF EXISTS _del_org_tables, _del_fk_edges, _del_remaining, _del_order;

      -- Step 1: collect all org-scoped tables (those with an organization_id column).
      CREATE TEMP TABLE _del_org_tables ON COMMIT DROP AS
      SELECT DISTINCT cls.relname::text AS tbl_name
      FROM pg_attribute att
      JOIN pg_class cls ON att.attrelid = cls.oid
      JOIN pg_namespace ns ON cls.relnamespace = ns.oid
      WHERE att.attname = 'organization_id'
        AND ns.nspname = 'public'
        AND cls.relkind = 'r'
        AND cls.relname != 'organizations'
        AND NOT att.attisdropped;

      -- Step 2: build FK dependency graph between org-scoped tables.
      -- Edge (from_tbl -> to_tbl) means from_tbl must be deleted BEFORE to_tbl.
      -- is_breakable = true when every FK column in the constraint is nullable,
      -- allowing a cycle to be resolved by nulling those columns for the org.
      CREATE TEMP TABLE _del_fk_edges ON COMMIT DROP AS
      SELECT
        con.oid                AS con_oid,
        from_cls.relname::text AS from_tbl,
        to_cls.relname::text   AS to_tbl,
        NOT EXISTS (
          SELECT 1
          FROM pg_attribute a,
               unnest(con.conkey) AS k(attnum)
          WHERE a.attrelid = con.conrelid
            AND a.attnum   = k.attnum
            AND a.attnotnull
        ) AS is_breakable
      FROM pg_constraint con
      JOIN pg_class from_cls ON from_cls.oid = con.conrelid
      JOIN pg_class to_cls   ON to_cls.oid   = con.confrelid
      JOIN pg_namespace ns   ON from_cls.relnamespace = ns.oid
      WHERE con.contype = 'f'
        AND ns.nspname = 'public'
        AND from_cls.relname != to_cls.relname
        AND from_cls.relname IN (SELECT tbl_name FROM _del_org_tables)
        AND to_cls.relname   IN (SELECT tbl_name FROM _del_org_tables);

      -- Tables not yet scheduled for deletion.
      CREATE TEMP TABLE _del_remaining ON COMMIT DROP AS
      SELECT tbl_name FROM _del_org_tables;

      -- Final deletion order produced by the topological sort.
      CREATE TEMP TABLE _del_order (ord INT, tbl_name TEXT) ON COMMIT DROP;

      -- Step 3: Kahn's algorithm with cycle-breaking.
      -- Each pass schedules every table that has no incoming edges from remaining
      -- tables (in-degree 0). When no table can be scheduled (cycle), we break the
      -- cycle by nulling the nullable FK for this org and removing that edge.
      LOOP
        EXIT WHEN NOT EXISTS (SELECT 1 FROM _del_remaining);

        v_progress := FALSE;

        FOR v_tbl IN
          SELECT r.tbl_name
          FROM _del_remaining r
          WHERE NOT EXISTS (
            SELECT 1 FROM _del_fk_edges e
            WHERE e.to_tbl = r.tbl_name
              AND e.from_tbl IN (SELECT tbl_name FROM _del_remaining)
              AND e.from_tbl != r.tbl_name
          )
          ORDER BY r.tbl_name
        LOOP
          v_progress := TRUE;
          INSERT INTO _del_order VALUES (v_ord, v_tbl);
          v_ord := v_ord + 1;
          DELETE FROM _del_remaining WHERE tbl_name = v_tbl;
        END LOOP;

        EXIT WHEN NOT EXISTS (SELECT 1 FROM _del_remaining);

        IF NOT v_progress THEN
          -- All remaining tables are in a cycle. Find a nullable FK edge to break it.
          SELECT e.con_oid, e.from_tbl
          INTO v_con_oid, v_from
          FROM _del_fk_edges e
          WHERE e.is_breakable
            AND e.from_tbl IN (SELECT tbl_name FROM _del_remaining)
            AND e.to_tbl   IN (SELECT tbl_name FROM _del_remaining)
          ORDER BY e.from_tbl, e.to_tbl
          LIMIT 1;

          IF NOT FOUND THEN
            RAISE EXCEPTION 'Circular FK with no nullable column to break among: %',
              (SELECT string_agg(tbl_name, ', ' ORDER BY tbl_name) FROM _del_remaining);
          END IF;

          -- Build "col1 = NULL, col2 = NULL" from the constraint's FK columns.
          SELECT string_agg(quote_ident(a.attname) || ' = NULL', ', ')
          INTO v_cols
          FROM pg_attribute a,
               unnest((SELECT conkey FROM pg_constraint WHERE oid = v_con_oid)) AS k(attnum)
          WHERE a.attrelid = (SELECT conrelid FROM pg_constraint WHERE oid = v_con_oid)
            AND a.attnum = k.attnum;

          -- Null out this FK for the org being deleted.
          EXECUTE format('UPDATE %I SET %s WHERE organization_id = %s', v_from, v_cols, org_id);
          RAISE NOTICE 'Cycle break: nulled [%] in % for org %', v_cols, v_from, org_id;

          -- Remove the broken edge so the sort can continue.
          DELETE FROM _del_fk_edges WHERE con_oid = v_con_oid;
        END IF;
      END LOOP;

      -- Step 4: delete in topological order.
      FOR v_tbl IN SELECT tbl_name FROM _del_order ORDER BY ord LOOP
        EXECUTE format('DELETE FROM %I WHERE organization_id = %s', v_tbl, org_id);
        GET DIAGNOSTICS v_deleted = ROW_COUNT;
        IF v_deleted > 0 THEN
          RAISE NOTICE 'Deleted % rows from %', v_deleted, v_tbl;
        END IF;
      END LOOP;
    END;
    $$ LANGUAGE plpgsql;
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
    $$ LANGUAGE plpgsql;
    """)
  end
end
