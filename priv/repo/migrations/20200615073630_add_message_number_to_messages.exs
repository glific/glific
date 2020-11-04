defmodule Glific.Repo.Migrations.AddMessageNumberToMessages do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION update_message_number()
    RETURNS trigger AS $$
    DECLARE message_ids BIGINT[];
    BEGIN
      IF (TG_OP = 'INSERT') THEN
        UPDATE messages set message_number = message_number + 1 where contact_id = NEW.contact_id and id < NEW.id;
        UPDATE messages  set message_number = 0 where id = NEW.id;
        UPDATE contacts  set last_message_at = CURRENT_TIMESTAMP where id = NEW.contact_id;
        RETURN NEW;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute "DROP TRIGGER IF EXISTS update_message_number_trigger ON messages;"

    execute """
    CREATE TRIGGER update_message_number_trigger
    AFTER INSERT
    ON messages
    FOR EACH ROW
    EXECUTE PROCEDURE update_message_number();
    """
  end

  def down do
    execute "DROP FUNCTION update_message_number() CASCADE;"
  end
end
