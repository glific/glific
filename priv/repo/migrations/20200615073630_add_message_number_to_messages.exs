defmodule Glific.Repo.Migrations.AddMessageNumberToMessages do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION update_message_number()
    RETURNS trigger AS $$
    DECLARE message_ids BIGINT[];
    DECLARE sessionlimit INT;
    DECLARE current_diff INT;
    DECLARE current_session_uuid UUID;

    BEGIN
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
      IF (TG_OP = 'INSERT') THEN
        UPDATE messages set message_number = message_number + 1 where contact_id = NEW.contact_id and id < NEW.id;
        UPDATE messages  set message_number = 0 where id = NEW.id;

        IF (NEW.flow = 'inbound') THEN
          sessionlimit := (SELECT session_limit * 60 FROM organizations WHERE id = NEW.organization_id LIMIT 1);
          current_diff := (SELECT EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) - EXTRACT(EPOCH FROM (SELECT last_message_at FROM contacts WHERE id = NEW.contact_id AND organization_id = NEW.organization_id LIMIT 1)));
          current_session_uuid := (SELECT session_uuid FROM messages
          WHERE contact_id = NEW.contact_id
          AND organization_id = NEW.organization_id
          AND flow = 'inbound'
          AND id != NEW.id
          ORDER BY id DESC LIMIT 1);

          IF (current_diff < sessionlimit AND current_session_uuid is not null) THEN
            UPDATE messages  set session_uuid = current_session_uuid where id = NEW.id;
          ELSE
            UPDATE messages set session_uuid = (SELECT uuid_generate_v4()) where id = NEW.id;
          END IF;

        END IF;

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
