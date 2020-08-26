defmodule Glific.Repo.Migrations.AddTriggerToTags do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION update_tag_parent()
    RETURNS trigger AS $$
    DECLARE tag_ids BIGINT[];
    BEGIN
      IF (TG_OP = 'INSERT') THEN
        tag_ids := Array(SELECT id from tags where parent_id = NEW.parent_id and id < NEW.id ORDER BY id ASC);
        
        UPDATE tags SET ancestors = array_append(tag_ids, parent_id) where id = NEW.id;
        RETURN NEW;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute "DROP TRIGGER IF EXISTS update_tag_parent_trigger ON tags;"

    execute """
    CREATE TRIGGER update_tag_parent_trigger
    AFTER INSERT
    ON tags
    FOR EACH ROW
    EXECUTE PROCEDURE update_tag_parent();
    """
  end

  def down do
    execute "DROP FUNCTION update_tag_parent() CASCADE;"
  end
end
