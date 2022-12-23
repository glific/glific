defmodule Glific.Repo.Migrations.AlterMessageNumberTrigger do
  use Ecto.Migration

  def change do
    message_before_insert_trigger()
    message_after_insert_trigger()
    drop_unwanted_triggers()
  end

  defp message_before_insert_trigger do
    execute("""
    CREATE OR REPLACE FUNCTION public.message_before_insert_callback()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $function$
    DECLARE now TIMESTAMP WITH TIME ZONE;
    DECLARE var_message_number BIGINT;
    DECLARE var_profile_id BIGINT;
    DECLARE var_context_id BIGINT;

    BEGIN
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

      IF (TG_OP = 'INSERT') THEN
        now := (CURRENT_TIMESTAMP at time zone 'utc');

        IF(NEW.sender_id = NEW.receiver_id AND NEW.group_id > 0) THEN
          SELECT last_message_number INTO var_message_number FROM groups WHERE id = NEW.group_id LIMIT 1;

          IF (var_message_number IS NULL) THEN
            var_message_number = 0;
          END IF;

          var_message_number = var_message_number + 1;

          UPDATE groups SET last_communication_at = now, last_message_number = var_message_number WHERE id = NEW.group_id;

          NEW.message_number = var_message_number;

        ELSE

          SELECT last_message_number,  active_profile_id INTO var_message_number, var_profile_id
          FROM contacts WHERE organization_id = NEW.organization_id AND id = NEW.contact_id LIMIT 1;

          NEW.profile_id = var_profile_id;

          var_message_number = var_message_number + 1;

          IF (NEW.flow = 'inbound') THEN

            IF (NEW.context_id IS NOT NULL) THEN
              SELECT id INTO var_context_id
              FROM messages
              WHERE bsp_message_id = NEW.context_id;
              NEW.context_message_id = var_context_id;
            END IF;

            UPDATE contacts SET
                last_communication_at = now,
                last_message_at = now,
                last_message_number = var_message_number,
                is_org_read = false,
                is_org_replied = false,
                is_contact_replied = true,
                updated_at = now
                WHERE id = NEW.contact_id;
          ELSE

            UPDATE contacts
              SET
                last_communication_at = now,
                last_message_number = var_message_number,
                is_org_replied = true,
                is_contact_replied = false,
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

    execute("DROP TRIGGER IF EXISTS message_before_insert_trigger ON messages;")

    execute("""
    CREATE TRIGGER message_before_insert_trigger
    BEFORE INSERT
    ON messages
    FOR EACH ROW
    EXECUTE PROCEDURE message_before_insert_callback();
    """)
  end

  defp message_after_insert_trigger() do
    execute("""
    CREATE OR REPLACE FUNCTION message_after_insert_callback()
      RETURNS trigger AS $$
      DECLARE session_lim BIGINT;
      DECLARE current_diff BIGINT;
      DECLARE current_session_uuid UUID;
      DECLARE session_uuid_value UUID;
      DECLARE var_message_at TIMESTAMP WITH TIME ZONE;

      BEGIN
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

      UPDATE organizations SET last_communication_at = (CURRENT_TIMESTAMP at time zone 'utc') WHERE id = NEW.organization_id;

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

        UPDATE messages set session_uuid = session_uuid_value where id = NEW.id;

      END IF;

        RETURN NEW;
      END;
    $$ LANGUAGE plpgsql;
    """)

    execute("DROP TRIGGER IF EXISTS message_after_insert_trigger ON messages;")

    execute("""
    CREATE TRIGGER message_after_insert_trigger
    AFTER INSERT
    ON messages
    FOR EACH ROW
    EXECUTE PROCEDURE message_after_insert_callback();
    """)
  end

  defp drop_unwanted_triggers() do
    [
      "DROP TRIGGER IF EXISTS update_message_number_trigger ON messages",
      "DROP TRIGGER IF EXISTS update_profile_id_on_new_message ON messages"
    ]
    |> Enum.each(&execute/1)
  end
end
