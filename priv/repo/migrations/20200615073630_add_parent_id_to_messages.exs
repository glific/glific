defmodule Glific.Repo.Migrations.AddParentIdToMessages do
  use Ecto.Migration

  @ancestors_limit Application.fetch_env!(:glific, :message_ancestors_limit)

  def up do
    execute """
    CREATE OR REPLACE FUNCTION update_message_parent()
    RETURNS trigger AS $$
    DECLARE message_ids BIGINT[];
    BEGIN
      IF (TG_OP = 'INSERT') THEN
        message_ids := Array(SELECT id from messages where contact_id = NEW.contact_id and id < NEW.id ORDER BY id DESC LIMIT #{@ancestors_limit} );

        UPDATE messages SET parent_id = message_ids[1], ancestors = message_ids where id = NEW.id;
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
