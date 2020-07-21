defmodule Glific.Repo.Migrations.SetTriggerForFlowRevisionNumber do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION update_flow_revision_number()
    RETURNS trigger AS $$
    BEGIN
      IF (TG_OP = 'INSERT') THEN
        UPDATE flow_revisions set revision_number = revision_number + 1 where flow_id= NEW.flow_id and id < NEW.id;
        RETURN NEW;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute "DROP TRIGGER IF EXISTS update_flow_revision_number_trigger ON flow_revisions;"

    execute """
    CREATE TRIGGER update_flow_revision_number_trigger
    AFTER INSERT
    ON flow_revisions
    FOR EACH ROW
    EXECUTE PROCEDURE update_flow_revision_number();
    """
  end

  def down do
    execute "DROP FUNCTION update_flow_revision_number() CASCADE;"
  end
end
