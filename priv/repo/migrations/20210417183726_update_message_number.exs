defmodule Glific.Repo.Migrations.UpdateMessageStatus do
  use Ecto.Migration

  def up do
    message_number_trigger()
  end

  defp message_number_trigger do
    execute """
    CREATE OR REPLACE FUNCTION public.update_message_number()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $function$
    DECLARE message_ids BIGINT[];
    DECLARE session_lim BIGINT;
    DECLARE current_diff BIGINT;
    DECLARE current_session_uuid UUID;
    DECLARE session_uuid_value UUID;
    DECLARE now TIMESTAMP WITH TIME ZONE;
    DECLARE var_message_at TIMESTAMP WITH TIME ZONE;
    DECLARE var_message_number BIGINT;
    DECLARE var_context_id BIGINT;

    BEGIN
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

      IF (TG_OP = 'INSERT') THEN
        now := (CURRENT_TIMESTAMP at time zone 'utc');

        UPDATE organizations
          SET last_communication_at = now
          WHERE id = NEW.organization_id;

        IF(NEW.group_id > 0 AND NEW.sender_id = NEW.receiver_id) THEN
          SELECT last_message_number INTO var_message_number FROM groups WHERE id = NEW.group_id LIMIT 1;
          IF (var_message_number IS NULL) THEN
            var_message_number = 0;
          END IF;

          NEW.message_number = var_message_number + 1;

          UPDATE groups
            SET
              last_communication_at = now,
              last_message_number = last_message_number + 1
            WHERE id = NEW.group_id;
        ELSE
          SELECT last_message_number, last_message_at INTO var_message_number, var_message_at
          FROM contacts
          WHERE id = NEW.contact_id AND organization_id = NEW.organization_id LIMIT 1;

          IF (NEW.flow = 'inbound') THEN
            SELECT session_limit * 60 INTO session_lim FROM organizations WHERE id = NEW.organization_id LIMIT 1;

            SELECT EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) - EXTRACT(EPOCH FROM var_message_at)
            INTO current_diff;

            SELECT session_uuid INTO current_session_uuid
            FROM messages
            WHERE contact_id = NEW.contact_id AND organization_id = NEW.organization_id AND flow = 'inbound'
               AND id != NEW.id  ORDER BY id DESC LIMIT 1;

            IF (current_diff < session_lim AND current_session_uuid IS NOT NULL) THEN
              session_uuid_value = current_session_uuid;
            ELSE
              session_uuid_value = (SELECT uuid_generate_v4());
            END IF;

            UPDATE contacts
              SET
                last_communication_at = now,
                last_message_at = now,
                last_message_number = last_message_number + 1,
                is_org_read = false,
                is_org_replied = false,
                is_contact_replied = true,
                updated_at = now,
              WHERE id = NEW.contact_id;

            IF (NEW.context_id IS NOT NULL) THEN
              SELECT id INTO var_context_id
              FROM messages
              WHERE bsp_message_id = NEW.context_id;

              NEW.context_message_id = var_context_id;
            END IF;

            NEW.message_number = var_message_number + 1;
            NEW.session_uuid = session_uuid_value;
          ELSE
            UPDATE contacts
              SET
                last_communication_at = now,
                last_message_number = last_message_number + 1,
                is_org_replied = true,
                is_contact_replied = false,
                updated_at = now,
              WHERE id = NEW.contact_id;

            NEW.message_number = var_message_number + 1;
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
    BEFORE INSERT
    ON messages
    FOR EACH ROW
    EXECUTE PROCEDURE update_message_number();
    """
  end

  def down do
    execute "DROP FUNCTION update_message_number() CASCADE;"
  end
end
