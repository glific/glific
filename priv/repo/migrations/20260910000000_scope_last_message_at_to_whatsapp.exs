defmodule Glific.Repo.Migrations.ScopeLastMessageAtToWhatsapp do
  @moduledoc """
  `contacts.last_message_at` is the WhatsApp 24-hour session window — an inbound message resets it,
  and every WhatsApp-session reader keys off it. The `message_before_insert_callback` trigger
  updated it for any inbound message regardless of `channel`, so a web-channel message (introduced
  in #5709/#5714) reset the WhatsApp window for a contact who only ever wrote in the browser and,
  after #5713, may never have consented to WhatsApp.

  Gate that one write to non-web channels. Everything else in the trigger —
  `last_communication_at`, `last_message_number`, the read/replied flags — is channel-agnostic
  inbox state and must keep updating so a web conversation still surfaces, sorts and badges.
  """
  use Ecto.Migration

  def up do
    execute(function_sql("CASE WHEN NEW.channel = 'web' THEN last_message_at ELSE now END"))
  end

  def down do
    execute(function_sql("now"))
  end

  defp function_sql(last_message_at_expr) do
    """
    CREATE OR REPLACE FUNCTION public.message_before_insert_callback() RETURNS trigger
        LANGUAGE plpgsql
        AS $$
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
                last_message_at = #{last_message_at_expr},
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
    $$;
    """
  end
end
