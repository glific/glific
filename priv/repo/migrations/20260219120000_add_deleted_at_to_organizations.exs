defmodule Glific.Repo.Migrations.AddDeletedAtToOrganizations do
  use Ecto.Migration

  def up do
    alter table(:organizations) do
      add(:deleted_at, :utc_datetime, null: true)
    end

    # Partial index for fast filtering of non-deleted organizations
    create index(:organizations, [:deleted_at],
      where: "deleted_at IS NULL",
      name: :organizations_active_index
    )

    # Replace shortcode unique constraint with partial unique index (only non-deleted orgs)
    drop_if_exists unique_index(:organizations, [:shortcode])
    execute("DROP INDEX IF EXISTS organizations_shortcode_index")

    create unique_index(:organizations, [:shortcode],
      where: "deleted_at IS NULL",
      name: :organizations_shortcode_active_index
    )

    # Replace contact_id unique constraint with partial unique index (only non-deleted orgs)
    drop_if_exists unique_index(:organizations, [:contact_id])
    execute("DROP INDEX IF EXISTS organizations_contact_id_index")

    create unique_index(:organizations, [:contact_id],
      where: "deleted_at IS NULL",
      name: :organizations_contact_id_active_index
    )

    create_delete_organization_data_function()
  end

  def down do
    execute("DROP FUNCTION IF EXISTS delete_organization_data(BIGINT)")

    drop_if_exists index(:organizations, [:deleted_at], name: :organizations_active_index)

    drop_if_exists unique_index(:organizations, [:shortcode],
                     name: :organizations_shortcode_active_index
                   )

    drop_if_exists unique_index(:organizations, [:contact_id],
                     name: :organizations_contact_id_active_index
                   )

    create unique_index(:organizations, [:shortcode])
    create unique_index(:organizations, [:contact_id])

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
      -- Null out foreign keys on the organization row to avoid FK violations
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
    END;
    $$ LANGUAGE plpgsql;
    """)
  end
end
