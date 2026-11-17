defmodule Glific.Repo.Migrations.RecordLastMessageAtOnWebIdentity do
  @moduledoc """
  Records when a contact last messaged on the web channel, so staff can see each channel's last
  activity on the contact profile (#5877).

  `message_before_insert_callback` already keeps that time for WhatsApp on the contact's
  `(whatsapp, phone)` identity. This adds the same for an inbound web message, on the contact's web
  identity. `contacts.last_message_at` is unchanged: it is the WhatsApp session clock, and a web
  message must not restart it.

  The web identity is matched on the contact alone, not on the phone: a contact who signed in with
  an NGO username has no phone, and its identifier is the username. A contact has at most one web
  identity in practice, and updating every one it has is still right.

  Locks are taken on `contacts` first and the identity second, as in the WhatsApp branch.
  """
  use Ecto.Migration

  def up do
    execute("""
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

            UPDATE contacts SET
                last_communication_at = now,
                last_message_at = CASE WHEN NEW.channel = 'web' THEN last_message_at ELSE now END,
                last_message_number = var_message_number,
                is_org_read = false,
                is_org_replied = false,
                is_contact_replied = true,
                updated_at = now
                WHERE id = NEW.contact_id;

            IF (NEW.channel IS DISTINCT FROM 'web') AND var_phone IS NOT NULL AND var_phone <> '' THEN
              UPDATE contact_identities
                SET last_message_at = now, updated_at = now
                WHERE contact_id = NEW.contact_id AND channel = 'whatsapp' AND identifier = var_phone;
            END IF;

            IF (NEW.channel = 'web') THEN
              UPDATE contact_identities
                SET last_message_at = now, updated_at = now
                WHERE contact_id = NEW.contact_id AND channel = 'web';
            END IF;

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
    """)
  end

  def down do
    execute("""
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

            UPDATE contacts SET
                last_communication_at = now,
                last_message_at = CASE WHEN NEW.channel = 'web' THEN last_message_at ELSE now END,
                last_message_number = var_message_number,
                is_org_read = false,
                is_org_replied = false,
                is_contact_replied = true,
                updated_at = now
                WHERE id = NEW.contact_id;

            IF (NEW.channel IS DISTINCT FROM 'web') AND var_phone IS NOT NULL AND var_phone <> '' THEN
              UPDATE contact_identities
                SET last_message_at = now, updated_at = now
                WHERE contact_id = NEW.contact_id AND channel = 'whatsapp' AND identifier = var_phone;
            END IF;

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
    """)
  end
end
