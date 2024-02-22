defmodule Glific.Repo.Migrations.AddTriggerForWaMessageNumber do
  use Ecto.Migration

  def change do
    wa_message_before_insert_trigger()
    # wa_message_after_insert_trigger()
  end

  defp wa_message_before_insert_trigger do
    execute("""
    CREATE OR REPLACE FUNCTION public.wa_message_before_insert_callback()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $function$
    DECLARE now TIMESTAMP WITH TIME ZONE;
    DECLARE var_message_number BIGINT;
    DECLARE var_context_id BIGINT;
    BEGIN
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
      IF (TG_OP = 'INSERT') THEN
        now := (CURRENT_TIMESTAMP at time zone 'utc');
        IF(NEW.sender_id = NEW.receiver_id AND NEW.group_id > 0) THEN
          SELECT wa_last_message_number INTO var_message_number FROM groups WHERE id = NEW.group_id LIMIT 1;
          IF (var_message_number IS NULL) THEN
            var_message_number = 0;
          END IF;
          var_message_number = var_message_number + 1;
          UPDATE groups SET wa_last_communication_at = now, wa_last_message_number = var_message_number WHERE id = NEW.group_id;
          NEW.message_number = var_message_number;
        ELSE
          SELECT wa_last_message_number INTO var_message_number
          FROM contacts WHERE organization_id = NEW.organization_id AND id = NEW.contact_id LIMIT 1;
          var_message_number = var_message_number + 1;
          IF (NEW.flow = 'inbound') THEN
            IF (NEW.context_id IS NOT NULL) THEN
              SELECT id INTO var_context_id
              FROM wa_messages
              WHERE bsp_message_id = NEW.context_id;
              NEW.context_message_id = var_context_id;
            END IF;
            UPDATE contacts SET
                wa_last_communication_at = now,
                wa_last_message_number = var_message_number,
                updated_at = now
                WHERE id = NEW.contact_id;
          ELSE
            UPDATE contacts
              SET
                wa_last_communication_at = now,
                wa_last_message_number = var_message_number,
                updated_at = now
              WHERE id = NEW.contact_id;
          END IF;
          NEW.message_number = var_message_number;
        END IF;
        RETURN NEW;
      END IF;
      RETURN NEW;
    END;
    $function$
    """)

    execute("DROP TRIGGER IF EXISTS wa_message_before_insert_trigger ON wa_messages;")

    execute("""
    CREATE TRIGGER wa_message_before_insert_trigger
    BEFORE INSERT
    ON wa_messages
    FOR EACH ROW
    EXECUTE PROCEDURE wa_message_before_insert_callback();
    """)
  end

  defp wa_message_after_insert_trigger() do
    execute("""
    CREATE OR REPLACE FUNCTION wa_message_after_insert_callback()
      RETURNS trigger AS $$
      DECLARE session_lim BIGINT;
      DECLARE current_diff BIGINT;
      DECLARE current_session_uuid UUID;
      DECLARE session_uuid_value UUID;
      DECLARE var_message_at TIMESTAMP WITH TIME ZONE;
      BEGIN
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
      UPDATE organizations SET wa_last_communication_at = (CURRENT_TIMESTAMP at time zone 'utc') WHERE id = NEW.organization_id;
      IF (NEW.flow = 'inbound') THEN
        SELECT session_limit * 60 INTO session_lim FROM organizations WHERE id = NEW.organization_id LIMIT 1;
        SELECT EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) - EXTRACT(EPOCH FROM var_message_at)
        INTO current_diff;
        SELECT session_uuid INTO current_session_uuid
        FROM wa_messages
        WHERE contact_id = NEW.contact_id AND organization_id = NEW.organization_id AND flow = 'inbound'
         AND id != NEW.id  ORDER BY id DESC LIMIT 1;
        IF (current_diff < session_lim AND current_session_uuid IS NOT NULL) THEN
          session_uuid_value = current_session_uuid;
        ELSE
          session_uuid_value = (SELECT uuid_generate_v4());
        END IF;
        UPDATE wa_messages set session_uuid = session_uuid_value where id = NEW.id;
      END IF;
        RETURN NEW;
      END;
    $$ LANGUAGE plpgsql;
    """)

    execute("DROP TRIGGER IF EXISTS wa_message_after_insert_trigger ON wa_messages;")

    execute("""
    CREATE TRIGGER wa_message_after_insert_trigger
    AFTER INSERT
    ON wa_messages
    FOR EACH ROW
    EXECUTE PROCEDURE wa_message_after_insert_callback();
    """)
  end
end
