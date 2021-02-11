defmodule Glific.Repo.Migrations.MessageTriggerStatus do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION update_message_number()
    RETURNS trigger AS $$
    DECLARE message_ids BIGINT[];
    DECLARE session_lim INT;
    DECLARE current_diff INT;
    DECLARE current_session_uuid UUID;

    BEGIN
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
      IF (TG_OP = 'INSERT') THEN

        UPDATE organizations SET last_communication_at = (CURRENT_TIMESTAMP at time zone 'utc') WHERE id = NEW.organization_id;

        IF(NEW.group_id > 0) THEN
          UPDATE messages  SET message_number = 0, is_read = true, is_replied = true WHERE id = NEW.id;
          UPDATE groups set last_communication_at = (CURRENT_TIMESTAMP at time zone 'utc') WHERE id = NEW.group_id;
          IF (New.sender_id = New.receiver_id) THEN
            UPDATE messages SET message_number = message_number + 1
              WHERE group_id = NEW.group_id AND sender_id = receiver_id AND id < NEW.id;
          ELSE
            UPDATE messages SET message_number = message_number + 1
              WHERE contact_id = NEW.contact_id AND id < NEW.id;
          END IF;
        ELSE
          UPDATE contacts SET last_communication_at = (CURRENT_TIMESTAMP at time zone 'utc') WHERE id = NEW.contact_id;
          UPDATE messages SET message_number = message_number + 1 WHERE contact_id = NEW.contact_id AND id < NEW.id;

          IF (NEW.flow = 'inbound') THEN
            UPDATE contacts set last_message_at = (CURRENT_TIMESTAMP at time zone 'utc') where id = NEW.contact_id;

            UPDATE messages SET message_number = 0, is_read = false, is_replied = false WHERE id = NEW.id;
            UPDATE messages SET is_read = true WHERE contact_id = NEW.contact_id AND id < NEW.id AND flow = 'inbound';
            UPDATE messages SET is_replied = true WHERE contact_id = NEW.contact_id AND id < NEW.id AND flow = 'outbound';

            session_lim := (SELECT session_limit * 60 FROM organizations WHERE id = NEW.organization_id LIMIT 1);
            current_diff :=
              (SELECT EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) -
               EXTRACT(EPOCH FROM (SELECT last_message_at FROM contacts
                 WHERE id = NEW.contact_id AND organization_id = NEW.organization_id LIMIT 1)));
            current_session_uuid := (SELECT session_uuid FROM messages
              WHERE contact_id = NEW.contact_id
              AND organization_id = NEW.organization_id
              AND flow = 'inbound'
              AND id != NEW.id
              ORDER BY id DESC LIMIT 1);

            IF (current_diff < session_lim AND current_session_uuid is not null) THEN
              UPDATE messages  set session_uuid = current_session_uuid where id = NEW.id;
            ELSE
              UPDATE messages set session_uuid = (SELECT uuid_generate_v4()) where id = NEW.id;
            END IF;
          ELSE
            UPDATE messages SET message_number = 0, is_read = true, is_replied = false WHERE id = NEW.id;
            UPDATE messages SET is_replied = true WHERE contact_id = NEW.contact_id AND id < NEW.id AND flow = 'inbound';
          END IF;
        END IF;

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
