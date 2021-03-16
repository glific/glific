defmodule Glific.Repo.Migrations.UpdateMessageStatus do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION public.update_message_number()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $function$
    DECLARE message_ids BIGINT[];
    DECLARE session_lim INT;
    DECLARE current_diff INT;
    DECLARE current_session_uuid UUID;
    DECLARE session_uuid_value UUID;

    BEGIN
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

      IF (TG_OP = 'INSERT') THEN

        UPDATE organizations SET last_communication_at = (CURRENT_TIMESTAMP at time zone 'utc') WHERE id = NEW.organization_id;

        IF(NEW.group_id > 0) THEN
          UPDATE messages
            SET message_number = 0, is_read = true, is_replied = true
            WHERE id = NEW.id;

          UPDATE groups
            SET last_communication_at = (CURRENT_TIMESTAMP at time zone 'utc')
            WHERE id = NEW.group_id;

          IF (New.sender_id = New.receiver_id) THEN
            UPDATE messages
              SET message_number = message_number + 1
              WHERE group_id = NEW.group_id AND sender_id = receiver_id AND id < NEW.id;
          ELSE
            UPDATE messages
              SET message_number = message_number + 1
              WHERE contact_id = NEW.contact_id AND id < NEW.id;
          END IF;
        ELSE
          IF (NEW.flow = 'inbound') THEN
            UPDATE contacts  SET last_communication_at = (CURRENT_TIMESTAMP at time zone 'utc'), last_message_at = (CURRENT_TIMESTAMP at time zone 'utc') WHERE id = NEW.contact_id;

            UPDATE messages SET message_number = message_number + 1, is_read = CASE WHEN flow = 'inbound' THEN true ELSE is_read END, is_replied = CASE WHEN flow = 'outbound' THEN true ELSE is_replied END WHERE contact_id = NEW.contact_id AND id < NEW.id;


            session_lim := (SELECT session_limit * 60 FROM organizations WHERE id = NEW.organization_id LIMIT 1);


            current_diff := (SELECT EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) - EXTRACT(EPOCH FROM (SELECT last_message_at FROM contacts  WHERE id = NEW.contact_id AND organization_id = NEW.organization_id LIMIT 1)));


            current_session_uuid := (SELECT session_uuid FROM messages WHERE contact_id = NEW.contact_id AND organization_id = NEW.organization_id AND flow = 'inbound'
              AND id != NEW.id  ORDER BY id DESC LIMIT 1);

            IF (current_diff < session_lim AND current_session_uuid IS NOT NULL) THEN
            	session_uuid_value = current_session_uuid;
            ELSE
              session_uuid_value = (SELECT uuid_generate_v4());
            END IF;


            UPDATE messages SET message_number = 0, is_read = false, is_replied = false, session_uuid = session_uuid_value WHERE id = NEW.id;
          ELSE

            UPDATE contacts SET last_communication_at = (CURRENT_TIMESTAMP at time zone 'utc') WHERE id = NEW.contact_id;

            UPDATE messages SET message_number = 0, is_read = true, is_replied = false WHERE id = NEW.id;

            UPDATE messages SET  message_number = message_number + 1,  is_replied = CASE  WHEN flow = 'inbound' THEN true ELSE is_replied END WHERE contact_id = NEW.contact_id AND id < NEW.id;
          END IF;

        END IF;

        RETURN NEW;

      END IF;
      RETURN NULL;
    END;
    $function$
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
