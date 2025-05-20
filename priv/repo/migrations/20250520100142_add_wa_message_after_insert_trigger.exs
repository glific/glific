defmodule Glific.Repo.Migrations.AddWaMessageAfterInsertTrigger do
  use Ecto.Migration

  def up do
    create_wa_message_after_insert_trigger()
  end

  def down do
    drop_trigger()
  end

  defp create_wa_message_after_insert_trigger do
    execute("""
    CREATE OR REPLACE FUNCTION public.wa_message_after_insert_callback()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $function$
    BEGIN
      UPDATE organizations SET last_communication_at = (CURRENT_TIMESTAMP at time zone 'utc') WHERE id = NEW.organization_id;
      RETURN NEW;
    END;
    $function$;
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

  defp drop_trigger do
    execute("DROP TRIGGER IF EXISTS wa_message_after_insert_trigger ON wa_messages;")
    execute("DROP FUNCTION IF EXISTS public.wa_message_after_insert_callback();")
  end
end
