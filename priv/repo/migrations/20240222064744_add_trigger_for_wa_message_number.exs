defmodule Glific.Repo.Migrations.AddTriggerForWaMessageNumber do
  use Ecto.Migration

  def change do
    wa_message_before_insert_trigger()
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
          SELECT wa_last_message_number INTO var_message_number
          FROM contacts WHERE organization_id = NEW.organization_id AND id = NEW.contact_id LIMIT 1;
          var_message_number = var_message_number + 1;
          IF (NEW.flow = 'inbound') THEN
            IF (NEW.context_id IS NOT NULL) THEN
              SELECT id INTO var_context_id
              FROM wa_messages
              WHERE bsp_id = NEW.context_id;
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
end
