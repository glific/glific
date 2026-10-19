defmodule Glific.Repo.Migrations.MoveLastMessageAtTriggerToWhatsappIdentity do
  @moduledoc """
  An inbound WhatsApp message restarts the 24 hour session, recorded as `last_message_at`. That clock now
  lives on the contact's `(whatsapp, phone)` identity, so `message_before_insert_callback` updates it there
  instead of on `contacts`. Everything else the trigger keeps on `contacts` (`last_communication_at`,
  `last_message_number`, the read/replied flags) is channel-agnostic inbox state and is unchanged.

  A contact whose WhatsApp identity row has not been backfilled yet gets the row inserted from its current
  `contacts` values, so the message never loses the session start.
  """
  use Ecto.Migration

  def up do
    execute(function_sql(new_inbound_sql(), "NEW.channel IS DISTINCT FROM 'web'"))
  end

  def down do
    execute(function_sql(old_inbound_sql(), "false"))
  end

  defp new_inbound_sql do
    """
    UPDATE contacts SET
                last_communication_at = now,
                last_message_number = var_message_number,
                is_org_read = false,
                is_org_replied = false,
                is_contact_replied = true,
                updated_at = now
                WHERE id = NEW.contact_id;
    """
  end

  defp old_inbound_sql do
    """
    UPDATE contacts SET
                last_communication_at = now,
                last_message_at = CASE WHEN NEW.channel = 'web' THEN last_message_at ELSE now END,
                last_message_number = var_message_number,
                is_org_read = false,
                is_org_replied = false,
                is_contact_replied = true,
                updated_at = now
                WHERE id = NEW.contact_id;
    """
  end

  defp function_sql(inbound_contact_update, whatsapp_session_condition) do
    """
    CREATE OR REPLACE FUNCTION public.message_before_insert_callback() RETURNS trigger
        LANGUAGE plpgsql
        AS $$
    DECLARE now TIMESTAMP WITH TIME ZONE;
    DECLARE var_message_number BIGINT;
    DECLARE var_profile_id BIGINT;
    DECLARE var_context_id BIGINT;
    DECLARE var_phone VARCHAR;

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

          SELECT last_message_number, active_profile_id, phone INTO var_message_number, var_profile_id, var_phone
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

            #{inbound_session_sql(whatsapp_session_condition)}

            #{inbound_contact_update}
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

  defp inbound_session_sql("false"), do: ""

  defp inbound_session_sql(condition) do
    """
    IF (#{condition}) AND var_phone IS NOT NULL AND var_phone <> '' THEN
              UPDATE contact_identities
                SET last_message_at = now, updated_at = now
                WHERE contact_id = NEW.contact_id AND channel = 'whatsapp' AND identifier = var_phone;

              IF NOT FOUND THEN
                INSERT INTO contact_identities (contact_id, organization_id, channel, identifier, optin_time,
                  optin_status, optin_method, optout_time, optout_method, bsp_status, last_message_at,
                  inserted_at, updated_at)
                SELECT id, organization_id, 'whatsapp', phone, optin_time, COALESCE(optin_status, false),
                  optin_method, optout_time, optout_method, bsp_status, now, now, now
                FROM contacts WHERE id = NEW.contact_id
                ON CONFLICT (organization_id, channel, identifier) DO NOTHING;
              END IF;
            END IF;
    """
  end
end
