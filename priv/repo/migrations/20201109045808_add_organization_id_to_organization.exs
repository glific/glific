defmodule Glific.Repo.Migrations.AddOrganizationIdToOrganization do
  use Ecto.Migration

  def up do
    alter table(:organizations) do
      add :organization_id, :bigint, null: true
    end

    # flush()

    execute """
    CREATE OR REPLACE FUNCTION update_organization_id()
    RETURNS trigger AS $$

    BEGIN
      UPDATE organizations set organization_id = id;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER update_organization_id_trigger
    AFTER INSERT
    ON organizations
    FOR EACH ROW
    EXECUTE PROCEDURE update_organization_id();
    """
  end

  def down do
    execute "DROP FUNCTION update_organization_id() CASCADE;"
  end
end
