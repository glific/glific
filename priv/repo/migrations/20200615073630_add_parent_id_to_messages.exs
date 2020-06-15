defmodule Glific.Repo.Migrations.AddParentIdToMessages do
  use Ecto.Migration

  @ancestors_limit Application.fetch_env!(:glific, :message_ancestors_limit)

  def up do
    execute """
    CREATE OR REPLACE FUNCTION update_message_parent()
    RETURNS trigger AS $$
    BEGIN
      IF (TG_OP = 'INSERT') THEN
        UPDATE messages SET parent_id = (SELECT id from messages where contact_id = NEW.contact_id and id < NEW.id ORDER BY id DESC LIMIT 1) where id = NEW.id;

        UPDATE messages SET ancestors = (Array(SELECT parent_id from messages where contact_id = NEW.contact_id and id < NEW.id and parent_id is not NULL ORDER BY id DESC LIMIT #{@ancestors_limit}))
        where id = NEW.id;

        RETURN NEW;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute "DROP TRIGGER IF EXISTS update_message_parent_trigger ON messages;"

    execute """
    CREATE TRIGGER update_message_parent_trigger
    AFTER INSERT
    ON messages
    FOR EACH ROW
    EXECUTE PROCEDURE update_message_parent();
    """
  end

  def down do
    execute "DROP FUNCTION update_message_parent() CASCADE;"
  end
end
