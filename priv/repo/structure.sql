--
-- PostgreSQL database dump
--

\restrict H2xfx7ERE4SrIeMiG3eYz7cFVhmyRKWtNmIzcMpTKJGeXmb5eiMQgq1gUC0CEim

-- Dumped from database version 17.7 (Postgres.app)
-- Dumped by pg_dump version 17.7 (Postgres.app)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: global; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA global;


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: oban_job_state; Type: TYPE; Schema: global; Owner: -
--

CREATE TYPE global.oban_job_state AS ENUM (
    'available',
    'suspended',
    'scheduled',
    'executing',
    'retryable',
    'completed',
    'discarded',
    'cancelled'
);


--
-- Name: ai_evaluation_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.ai_evaluation_status_enum AS ENUM (
    'create_in_progress',
    'processing',
    'failed',
    'completed'
);


--
-- Name: api_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.api_status_enum AS ENUM (
    'ok',
    'error'
);


--
-- Name: assistant_config_version_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.assistant_config_version_status_enum AS ENUM (
    'in_progress',
    'ready',
    'failed'
);


--
-- Name: certificate_template_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.certificate_template_type_enum AS ENUM (
    'slides'
);


--
-- Name: contact_field_scope_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.contact_field_scope_enum AS ENUM (
    'contact',
    'globals',
    'wa_group'
);


--
-- Name: contact_field_value_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.contact_field_value_type_enum AS ENUM (
    'text',
    'integer',
    'number',
    'boolean',
    'date'
);


--
-- Name: contact_provider_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.contact_provider_status_enum AS ENUM (
    'none',
    'session',
    'session_and_hsm',
    'hsm'
);


--
-- Name: contact_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.contact_status_enum AS ENUM (
    'blocked',
    'failed',
    'invalid',
    'processing',
    'valid'
);


--
-- Name: flow_action_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.flow_action_type_enum AS ENUM (
    'enter_flow',
    'send_msg',
    'set_contact_language',
    'wait_for_response',
    'set_contact_field'
);


--
-- Name: flow_case_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.flow_case_enum AS ENUM (
    'has_any_word'
);


--
-- Name: flow_router_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.flow_router_enum AS ENUM (
    'switch'
);


--
-- Name: flow_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.flow_type_enum AS ENUM (
    'message',
    'web_message'
);


--
-- Name: import_contacts_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.import_contacts_type_enum AS ENUM (
    'file_path',
    'url',
    'data'
);


--
-- Name: interactive_message_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.interactive_message_type_enum AS ENUM (
    'list',
    'quick_reply',
    'location_request_message',
    'blocks'
);


--
-- Name: knowledge_base_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.knowledge_base_status_enum AS ENUM (
    'in_progress',
    'completed',
    'failed'
);


--
-- Name: message_flow_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.message_flow_enum AS ENUM (
    'inbound',
    'outbound'
);


--
-- Name: message_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.message_status_enum AS ENUM (
    'sent',
    'delivered',
    'enqueued',
    'error',
    'read',
    'received',
    'contact_opt_out',
    'reached',
    'seen',
    'played',
    'deleted'
);


--
-- Name: message_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.message_type_enum AS ENUM (
    'audio',
    'contact',
    'document',
    'hsm',
    'image',
    'location',
    'list',
    'quick_reply',
    'text',
    'video',
    'sticker',
    'location_request_message',
    'poll',
    'whatsapp_form_response',
    'blocks',
    'blocks_response'
);


--
-- Name: organization_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.organization_status_enum AS ENUM (
    'inactive',
    'approved',
    'active',
    'suspended',
    'ready_to_delete',
    'forced_suspension'
);


--
-- Name: question_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.question_type_enum AS ENUM (
    'text',
    'numeric',
    'date'
);


--
-- Name: sheet_sync_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.sheet_sync_status_enum AS ENUM (
    'success',
    'failed'
);


--
-- Name: sort_order_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.sort_order_enum AS ENUM (
    'asc',
    'desc'
);


--
-- Name: template_button_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.template_button_type_enum AS ENUM (
    'call_to_action',
    'quick_reply',
    'otp',
    'whatsapp_form'
);


--
-- Name: user_roles_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_roles_enum AS ENUM (
    'none',
    'staff',
    'manager',
    'admin',
    'glific_admin'
);


--
-- Name: whatsapp_forms_category_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.whatsapp_forms_category_enum AS ENUM (
    'sign_up',
    'sign_in',
    'appointment_booking',
    'lead_generation',
    'contact_us',
    'customer_support',
    'survey',
    'other'
);


--
-- Name: whatsapp_forms_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.whatsapp_forms_status_enum AS ENUM (
    'draft',
    'published',
    'inactive'
);


--
-- Name: oban_state_to_bit(global.oban_job_state); Type: FUNCTION; Schema: global; Owner: -
--

CREATE FUNCTION global.oban_state_to_bit(state global.oban_job_state) RETURNS jsonb
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT CASE
       WHEN state = 'scheduled' THEN '0'::jsonb
       WHEN state = 'available' THEN '1'::jsonb
       WHEN state = 'executing' THEN '2'::jsonb
       WHEN state = 'retryable' THEN '3'::jsonb
       WHEN state = 'completed' THEN '4'::jsonb
       WHEN state = 'cancelled' THEN '5'::jsonb
       WHEN state = 'discarded' THEN '6'::jsonb
       END;
$$;


--
-- Name: message_after_insert_callback(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.message_after_insert_callback() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: message_before_insert_callback(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.message_before_insert_callback() RETURNS trigger
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
$$;


--
-- Name: remove_old_history(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_old_history() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    with ranked as (SELECT id, row_number() over (partition by contact_id order by updated_at desc) as rn
       from contact_histories where id <> NEW.id and contact_id = NEW.contact_id
     )
     delete from contact_histories
     where id in (select id  from ranked where rn >= 25);

     RETURN NEW;
  END;

$$;


--
-- Name: set_assistant_config_version_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_assistant_config_version_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM id FROM assistants WHERE id = NEW.assistant_id FOR UPDATE;

  SELECT COALESCE(MAX(version_number), 0) + 1
  INTO NEW.version_number
  FROM assistant_config_versions
  WHERE assistant_id = NEW.assistant_id;

  RETURN NEW;
END;
$$;


--
-- Name: set_knowledge_base_version_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_knowledge_base_version_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

  PERFORM id FROM knowledge_bases WHERE id = NEW.knowledge_base_id FOR UPDATE;
  SELECT COALESCE(MAX(version_number), 0) + 1
  INTO NEW.version_number
  FROM knowledge_base_versions
  WHERE knowledge_base_id = NEW.knowledge_base_id;

  RETURN NEW;
END;
$$;


--
-- Name: set_whatsapp_form_revision_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_whatsapp_form_revision_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  next_revision_number INTEGER;
BEGIN
  IF NEW.revision_number IS NULL THEN
    SELECT COALESCE(MAX(revision_number), 0) + 1
    INTO next_revision_number
    FROM whatsapp_form_revisions
    WHERE whatsapp_form_id = NEW.whatsapp_form_id;

    NEW.revision_number := next_revision_number;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: update_contact_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_contact_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

  BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN

      UPDATE contacts set updated_at = (CURRENT_TIMESTAMP at time zone 'utc') where id = NEW.contact_id;
    ELSE
      IF (TG_OP = 'DELETE') THEN
        UPDATE contacts set updated_at = (CURRENT_TIMESTAMP at time zone 'utc') where id = old.contact_id;

      END IF;
    END IF;
    RETURN NULL;
  END;
$$;


--
-- Name: update_contact_updated_at_on_tagging(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_contact_updated_at_on_tagging() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

  BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN

      UPDATE contacts set updated_at = (CURRENT_TIMESTAMP at time zone 'utc') where id = NEW.contact_id;
    ELSE
      IF (TG_OP = 'DELETE') THEN
        UPDATE contacts set updated_at = (CURRENT_TIMESTAMP at time zone 'utc') where id = old.contact_id;

      END IF;
    END IF;
    RETURN NULL;
  END;
$$;


--
-- Name: update_flow_revision_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_flow_revision_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    UPDATE flow_revisions set revision_number = revision_number + 1 where flow_id= NEW.flow_id and id < NEW.id;
    RETURN NEW;
  END IF;
  RETURN NULL;
END;
$$;


--
-- Name: update_message_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_message_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
            last_message_number = var_message_number + 1,
            is_org_read = false,
            is_org_replied = false,
            is_contact_replied = true,
            updated_at = now
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
            last_message_number = var_message_number + 1,
            is_org_replied = true,
            is_contact_replied = false,
            updated_at = now
          WHERE id = NEW.contact_id;

        NEW.message_number = var_message_number + 1;
      END IF;

    END IF;

    RETURN NEW;

  END IF;
  RETURN NULL;
END;
$$;


--
-- Name: update_message_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_message_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

  BEGIN
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN

      UPDATE messages set updated_at = (CURRENT_TIMESTAMP at time zone 'utc') where id = NEW.message_id;
    ELSE
      IF (TG_OP = 'DELETE') THEN
      UPDATE messages set updated_at = (CURRENT_TIMESTAMP at time zone 'utc') where id = old.message_id;

      END IF;
    END IF;
    RETURN NULL;
  END;
$$;


--
-- Name: update_organization_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_organization_id() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN
  UPDATE organizations set organization_id = id;
  RETURN NULL;
END;
$$;


--
-- Name: update_profile_id_on_new_contact_history(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_profile_id_on_new_contact_history() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

  BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    IF (TG_OP = 'INSERT') THEN
      UPDATE contact_histories set profile_id = (SELECT active_profile_id FROM contacts WHERE id = New.contact_id) where id = New.id;
    END IF;
    RETURN NULL;
  END;
$$;


--
-- Name: update_profile_id_on_new_flow_context(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_profile_id_on_new_flow_context() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

  BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    IF (TG_OP = 'INSERT') THEN
      UPDATE flow_contexts set profile_id = (SELECT active_profile_id FROM contacts WHERE id = New.contact_id) where id = New.id;
    END IF;
    RETURN NULL;
  END;
$$;


--
-- Name: update_profile_id_on_new_flow_result(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_profile_id_on_new_flow_result() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

  BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    IF (TG_OP = 'INSERT') THEN
      UPDATE flow_results set profile_id = (SELECT active_profile_id FROM contacts WHERE id = New.contact_id) where id = New.id;
    END IF;
    RETURN NULL;
  END;
$$;


--
-- Name: update_profile_id_on_new_message(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_profile_id_on_new_message() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

  BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
      UPDATE messages set profile_id = (SELECT active_profile_id FROM contacts WHERE id = New.contact_id) where id = New.id;
    RETURN NULL;
  END;
$$;


--
-- Name: update_tag_ancestors(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_tag_ancestors() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  WITH RECURSIVE parents AS
  (
    SELECT id AS id, ARRAY [id] AS ancestry
    FROM tags WHERE parent_id IS NULL UNION
    SELECT child.id AS id, array_append(p.ancestry, child.id) AS ancestry
    FROM tags child INNER JOIN parents p ON p.id = child.parent_id
  )
  UPDATE tags SET ancestors = (select array_remove(parents.ancestry, tags.id) as ancestry from parents where parents.id = tags.id);

  RETURN NULL;
END;
$$;


--
-- Name: wa_message_after_insert_callback(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.wa_message_after_insert_callback() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE organizations SET last_communication_at = (CURRENT_TIMESTAMP at time zone 'utc') WHERE id = NEW.organization_id;
  RETURN NEW;
END;
$$;


--
-- Name: wa_message_before_insert_callback(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.wa_message_before_insert_callback() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE now TIMESTAMP WITH TIME ZONE;
DECLARE var_message_number BIGINT;
DECLARE var_context_id BIGINT;
BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  IF (TG_OP = 'INSERT') THEN
    now := (CURRENT_TIMESTAMP at time zone 'utc');
      SELECT last_message_number INTO var_message_number
      FROM wa_groups WHERE organization_id = NEW.organization_id AND id = NEW.wa_group_id LIMIT 1;
      var_message_number = var_message_number + 1;
      IF (NEW.flow = 'inbound') THEN
        IF (NEW.context_id IS NOT NULL) THEN
          SELECT id INTO var_context_id
          FROM wa_messages
          WHERE bsp_id = NEW.context_id;
          NEW.context_message_id = var_context_id;
        END IF;
        UPDATE wa_groups SET
            last_communication_at = now,
            last_message_number = var_message_number,
            updated_at = now
            WHERE id = NEW.wa_group_id;
      ELSE
        UPDATE wa_groups
          SET
            last_communication_at = now,
            last_message_number = var_message_number,
            updated_at = now
          WHERE id = NEW.wa_group_id;
      END IF;
      NEW.message_number = var_message_number;
    RETURN NEW;
  END IF;
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: fun_with_flags_toggles; Type: TABLE; Schema: global; Owner: -
--

CREATE TABLE global.fun_with_flags_toggles (
    id bigint NOT NULL,
    flag_name character varying(255) NOT NULL,
    gate_type character varying(255) NOT NULL,
    target character varying(255) NOT NULL,
    enabled boolean NOT NULL
);


--
-- Name: fun_with_flags_toggles_id_seq; Type: SEQUENCE; Schema: global; Owner: -
--

CREATE SEQUENCE global.fun_with_flags_toggles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fun_with_flags_toggles_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: -
--

ALTER SEQUENCE global.fun_with_flags_toggles_id_seq OWNED BY global.fun_with_flags_toggles.id;


--
-- Name: languages; Type: TABLE; Schema: global; Owner: -
--

CREATE TABLE global.languages (
    id bigint NOT NULL,
    label character varying(255) NOT NULL,
    label_locale character varying(255) NOT NULL,
    description text,
    locale character varying(255) NOT NULL,
    is_active boolean DEFAULT true,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    localized boolean DEFAULT false
);


--
-- Name: TABLE languages; Type: COMMENT; Schema: global; Owner: -
--

COMMENT ON TABLE global.languages IS 'Languages table to optimize and switch between languages relatively quickly';


--
-- Name: COLUMN languages.label; Type: COMMENT; Schema: global; Owner: -
--

COMMENT ON COLUMN global.languages.label IS 'Language label, typically the full name - like English (US) or Hindi';


--
-- Name: COLUMN languages.label_locale; Type: COMMENT; Schema: global; Owner: -
--

COMMENT ON COLUMN global.languages.label_locale IS 'The language label in its default locale, e.g: हिंदी';


--
-- Name: COLUMN languages.description; Type: COMMENT; Schema: global; Owner: -
--

COMMENT ON COLUMN global.languages.description IS 'Optional description for the language';


--
-- Name: COLUMN languages.locale; Type: COMMENT; Schema: global; Owner: -
--

COMMENT ON COLUMN global.languages.locale IS 'The locale name of the language dialect, e.g. en, or hi';


--
-- Name: COLUMN languages.is_active; Type: COMMENT; Schema: global; Owner: -
--

COMMENT ON COLUMN global.languages.is_active IS 'Whether language currently in use within the system or not';


--
-- Name: languages_id_seq; Type: SEQUENCE; Schema: global; Owner: -
--

CREATE SEQUENCE global.languages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: languages_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: -
--

ALTER SEQUENCE global.languages_id_seq OWNED BY global.languages.id;


--
-- Name: oban_crons; Type: TABLE; Schema: global; Owner: -
--

CREATE TABLE global.oban_crons (
    name text NOT NULL,
    expression text NOT NULL,
    worker text NOT NULL,
    opts jsonb NOT NULL,
    insertions timestamp without time zone[] DEFAULT ARRAY[]::timestamp without time zone[] NOT NULL,
    paused boolean DEFAULT false NOT NULL,
    lock_version integer DEFAULT 1,
    inserted_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: oban_jobs; Type: TABLE; Schema: global; Owner: -
--

CREATE TABLE global.oban_jobs (
    id bigint NOT NULL,
    state global.oban_job_state DEFAULT 'available'::global.oban_job_state NOT NULL,
    queue text DEFAULT 'default'::text NOT NULL,
    worker text NOT NULL,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    attempt integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 20 NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    attempted_at timestamp without time zone,
    completed_at timestamp without time zone,
    attempted_by text[],
    discarded_at timestamp without time zone,
    priority integer DEFAULT 0 NOT NULL,
    tags character varying(255)[] DEFAULT ARRAY[]::character varying[],
    meta jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp without time zone,
    uniq_key text GENERATED ALWAYS AS (
CASE
    WHEN ((meta -> 'uniq_bmp'::text) @> global.oban_state_to_bit(state)) THEN (meta ->> 'uniq_key'::text)
    ELSE NULL::text
END) STORED,
    partition_key text GENERATED ALWAYS AS (
CASE
    WHEN (meta ? 'partition_key'::text) THEN (meta ->> 'partition_key'::text)
    ELSE NULL::text
END) STORED,
    CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
    CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
    CONSTRAINT queue_length CHECK (((char_length(queue) > 0) AND (char_length(queue) < 128))),
    CONSTRAINT worker_length CHECK (((char_length(worker) > 0) AND (char_length(worker) < 128)))
);


--
-- Name: TABLE oban_jobs; Type: COMMENT; Schema: global; Owner: -
--

COMMENT ON TABLE global.oban_jobs IS '14';


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE; Schema: global; Owner: -
--

CREATE SEQUENCE global.oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: -
--

ALTER SEQUENCE global.oban_jobs_id_seq OWNED BY global.oban_jobs.id;


--
-- Name: oban_peers; Type: TABLE; Schema: global; Owner: -
--

CREATE UNLOGGED TABLE global.oban_peers (
    name text NOT NULL,
    node text NOT NULL,
    started_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL
);


--
-- Name: oban_producers; Type: TABLE; Schema: global; Owner: -
--

CREATE UNLOGGED TABLE global.oban_producers (
    uuid uuid NOT NULL,
    name text NOT NULL,
    node text NOT NULL,
    queue text NOT NULL,
    meta jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: TABLE oban_producers; Type: COMMENT; Schema: global; Owner: -
--

COMMENT ON TABLE global.oban_producers IS '1.6.0-schemas,1.6.0-indexes';


--
-- Name: oban_queues; Type: TABLE; Schema: global; Owner: -
--

CREATE TABLE global.oban_queues (
    name text NOT NULL,
    opts jsonb DEFAULT '{}'::jsonb NOT NULL,
    "only" jsonb DEFAULT '{}'::jsonb NOT NULL,
    lock_version integer DEFAULT 1,
    inserted_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    hash text
);


--
-- Name: permissions; Type: TABLE; Schema: global; Owner: -
--

CREATE TABLE global.permissions (
    id bigint NOT NULL,
    entity character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: permissions_id_seq; Type: SEQUENCE; Schema: global; Owner: -
--

CREATE SEQUENCE global.permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: -
--

ALTER SEQUENCE global.permissions_id_seq OWNED BY global.permissions.id;


--
-- Name: providers; Type: TABLE; Schema: global; Owner: -
--

CREATE TABLE global.providers (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    shortcode character varying(255),
    "group" character varying(255),
    is_required boolean DEFAULT false,
    keys jsonb DEFAULT '{}'::jsonb,
    secrets jsonb DEFAULT '{}'::jsonb,
    description text
);


--
-- Name: COLUMN providers.name; Type: COMMENT; Schema: global; Owner: -
--

COMMENT ON COLUMN global.providers.name IS 'Name of the provider';


--
-- Name: COLUMN providers.shortcode; Type: COMMENT; Schema: global; Owner: -
--

COMMENT ON COLUMN global.providers.shortcode IS 'Shortcode for the provider';


--
-- Name: COLUMN providers.is_required; Type: COMMENT; Schema: global; Owner: -
--

COMMENT ON COLUMN global.providers.is_required IS 'Whether mandatory for initial setup';


--
-- Name: COLUMN providers.keys; Type: COMMENT; Schema: global; Owner: -
--

COMMENT ON COLUMN global.providers.keys IS 'JSON Object containing details of the URLs, labels, workers etc. of the provider';


--
-- Name: COLUMN providers.secrets; Type: COMMENT; Schema: global; Owner: -
--

COMMENT ON COLUMN global.providers.secrets IS 'JSON object containing details of the API keys for the provider';


--
-- Name: providers_id_seq; Type: SEQUENCE; Schema: global; Owner: -
--

CREATE SEQUENCE global.providers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: providers_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: -
--

ALTER SEQUENCE global.providers_id_seq OWNED BY global.providers.id;


--
-- Name: ai_evaluations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_evaluations (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    status public.ai_evaluation_status_enum DEFAULT 'create_in_progress'::public.ai_evaluation_status_enum NOT NULL,
    failure_reason character varying(255),
    results jsonb DEFAULT '{}'::jsonb,
    kaapi_evaluation_id integer,
    assistant_config_version_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    golden_qa_id bigint NOT NULL
);


--
-- Name: ai_evaluations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_evaluations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_evaluations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_evaluations_id_seq OWNED BY public.ai_evaluations.id;


--
-- Name: ask_glific_conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ask_glific_conversations (
    id bigint NOT NULL,
    conversation_id character varying(255) NOT NULL,
    user_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: ask_glific_conversations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ask_glific_conversations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ask_glific_conversations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ask_glific_conversations_id_seq OWNED BY public.ask_glific_conversations.id;


--
-- Name: assistant_config_version_knowledge_base_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assistant_config_version_knowledge_base_versions (
    id bigint NOT NULL,
    assistant_config_version_id bigint NOT NULL,
    knowledge_base_version_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN assistant_config_version_knowledge_base_versions.assistant_config_version_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_version_knowledge_base_versions.assistant_config_version_id IS 'Assistant config version id';


--
-- Name: COLUMN assistant_config_version_knowledge_base_versions.knowledge_base_version_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_version_knowledge_base_versions.knowledge_base_version_id IS 'Knowledge base version id';


--
-- Name: COLUMN assistant_config_version_knowledge_base_versions.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_version_knowledge_base_versions.organization_id IS 'Unique organization ID.';


--
-- Name: assistant_config_version_knowledge_base_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.assistant_config_version_knowledge_base_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: assistant_config_version_knowledge_base_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.assistant_config_version_knowledge_base_versions_id_seq OWNED BY public.assistant_config_version_knowledge_base_versions.id;


--
-- Name: assistant_config_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assistant_config_versions (
    id bigint NOT NULL,
    version_number integer NOT NULL,
    description text,
    prompt text NOT NULL,
    provider character varying(255) DEFAULT 'openai'::character varying NOT NULL,
    model character varying(255) NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb,
    status public.assistant_config_version_status_enum DEFAULT 'in_progress'::public.assistant_config_version_status_enum NOT NULL,
    failure_reason text,
    deleted_at timestamp(0) without time zone,
    organization_id bigint NOT NULL,
    assistant_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    kaapi_version_number integer
);


--
-- Name: COLUMN assistant_config_versions.version_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_versions.version_number IS 'Monotonically increasing config version per assistant';


--
-- Name: COLUMN assistant_config_versions.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_versions.description IS 'Description for this version';


--
-- Name: COLUMN assistant_config_versions.prompt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_versions.prompt IS 'Prompt/instructions for this version';


--
-- Name: COLUMN assistant_config_versions.provider; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_versions.provider IS 'LLM provider for this version';


--
-- Name: COLUMN assistant_config_versions.model; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_versions.model IS 'Model used by this version';


--
-- Name: COLUMN assistant_config_versions.settings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_versions.settings IS 'Provider-specific settings like temperature, etc.';


--
-- Name: COLUMN assistant_config_versions.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_versions.status IS 'Status of this version - in_progress, ready, failed';


--
-- Name: COLUMN assistant_config_versions.failure_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_versions.failure_reason IS 'Failure reason if status is failed';


--
-- Name: COLUMN assistant_config_versions.deleted_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_versions.deleted_at IS 'Soft-delete timestamp';


--
-- Name: COLUMN assistant_config_versions.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_versions.organization_id IS 'Unique organization ID.';


--
-- Name: COLUMN assistant_config_versions.assistant_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistant_config_versions.assistant_id IS 'Assistant this configuration belongs to';


--
-- Name: assistant_config_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.assistant_config_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: assistant_config_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.assistant_config_versions_id_seq OWNED BY public.assistant_config_versions.id;


--
-- Name: assistants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assistants (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    assistant_display_id character varying(255),
    kaapi_uuid character varying(255),
    active_config_version_id bigint,
    clone_status character varying(255) DEFAULT 'none'::character varying
);


--
-- Name: COLUMN assistants.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistants.name IS 'Name of the assistant';


--
-- Name: COLUMN assistants.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistants.description IS 'Description of the assistant';


--
-- Name: COLUMN assistants.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistants.organization_id IS 'Unique organization ID.';


--
-- Name: COLUMN assistants.assistant_display_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistants.assistant_display_id IS 'OpenAI-style assistant ID to display in the UI';


--
-- Name: COLUMN assistants.kaapi_uuid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistants.kaapi_uuid IS 'Kaapi UUID for the config';


--
-- Name: COLUMN assistants.active_config_version_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assistants.active_config_version_id IS 'Reference to the currently active configuration version';


--
-- Name: assistants_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.assistants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: assistants_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.assistants_id_seq OWNED BY public.assistants.id;


--
-- Name: bigquery_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bigquery_jobs (
    id bigint NOT NULL,
    "table" character varying(255),
    table_id integer,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    last_updated_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: COLUMN bigquery_jobs."table"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bigquery_jobs."table" IS 'Table name';


--
-- Name: COLUMN bigquery_jobs.table_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bigquery_jobs.table_id IS 'Table ID';


--
-- Name: COLUMN bigquery_jobs.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bigquery_jobs.organization_id IS 'Unique organization ID';


--
-- Name: COLUMN bigquery_jobs.last_updated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bigquery_jobs.last_updated_at IS 'Time when the record updated on bigquery';


--
-- Name: bigquery_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bigquery_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bigquery_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bigquery_jobs_id_seq OWNED BY public.bigquery_jobs.id;


--
-- Name: billings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billings (
    id bigint NOT NULL,
    stripe_customer_id character varying(255),
    stripe_payment_method_id character varying(255),
    stripe_subscription_id character varying(255),
    stripe_subscription_status character varying(255),
    stripe_subscription_items jsonb DEFAULT '{}'::jsonb,
    stripe_current_period_start timestamp(0) without time zone,
    stripe_current_period_end timestamp(0) without time zone,
    stripe_last_usage_recorded timestamp(0) without time zone,
    name character varying(255),
    email character varying(255),
    currency character varying(255),
    is_delinquent boolean,
    is_active boolean DEFAULT true,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    deduct_tds boolean DEFAULT false,
    tds_amount double precision DEFAULT 0,
    billing_period character varying(255)
);


--
-- Name: COLUMN billings.stripe_subscription_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billings.stripe_subscription_items IS 'A map of stripe subscription item ids to our price and product ids';


--
-- Name: COLUMN billings.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billings.name IS 'Billing Contact Name, used to create the Stripe Customer';


--
-- Name: COLUMN billings.email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billings.email IS 'Billing Email Address, used to create the Stripe Customer';


--
-- Name: COLUMN billings.currency; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billings.currency IS 'Currency the account will pay bills';


--
-- Name: COLUMN billings.is_delinquent; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billings.is_delinquent IS 'Is this account delinquent? Invoice table will have more info';


--
-- Name: COLUMN billings.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billings.is_active IS 'Is this the active billing record for this organization';


--
-- Name: COLUMN billings.deduct_tds; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billings.deduct_tds IS 'check if we should deduct the tds or not';


--
-- Name: COLUMN billings.tds_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billings.tds_amount IS '% of tds deduction on principle amount';


--
-- Name: COLUMN billings.billing_period; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billings.billing_period IS 'stores the subscription billing period for a customer';


--
-- Name: billings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.billings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: billings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.billings_id_seq OWNED BY public.billings.id;


--
-- Name: certificate_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.certificate_templates (
    id bigint NOT NULL,
    label character varying(255) NOT NULL,
    url character varying(255) NOT NULL,
    description text,
    type public.certificate_template_type_enum DEFAULT 'slides'::public.certificate_template_type_enum,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN certificate_templates.label; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.certificate_templates.label IS 'Title of the certificate template';


--
-- Name: COLUMN certificate_templates.url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.certificate_templates.url IS 'Url of the certificate template';


--
-- Name: COLUMN certificate_templates.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.certificate_templates.description IS 'Details about the certificate template';


--
-- Name: COLUMN certificate_templates.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.certificate_templates.type IS 'Format of template used for ex: slides, pdf etc..';


--
-- Name: COLUMN certificate_templates.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.certificate_templates.organization_id IS 'Unique organization ID.';


--
-- Name: certificate_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.certificate_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: certificate_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.certificate_templates_id_seq OWNED BY public.certificate_templates.id;


--
-- Name: consulting_hours; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.consulting_hours (
    id bigint NOT NULL,
    organization_id bigint,
    organization_name character varying(255),
    participants text,
    staff text,
    "when" timestamp(0) without time zone,
    duration integer,
    content text,
    is_billable boolean DEFAULT true,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: TABLE consulting_hours; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.consulting_hours IS 'Lets track consulting hours here';


--
-- Name: COLUMN consulting_hours.organization_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.consulting_hours.organization_name IS 'Record of who we billed in case we delete the organization';


--
-- Name: COLUMN consulting_hours.participants; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.consulting_hours.participants IS 'Name of NGO participants';


--
-- Name: COLUMN consulting_hours.staff; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.consulting_hours.staff IS 'Name of staff members who were on the call';


--
-- Name: COLUMN consulting_hours."when"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.consulting_hours."when" IS 'Date and time of when the support call happened';


--
-- Name: COLUMN consulting_hours.duration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.consulting_hours.duration IS 'Minutes spent on call, round up to 15 minute intervals';


--
-- Name: COLUMN consulting_hours.content; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.consulting_hours.content IS 'Agenda, and action items of the call';


--
-- Name: COLUMN consulting_hours.is_billable; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.consulting_hours.is_billable IS 'Is this call billable';


--
-- Name: consulting_hours_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.consulting_hours_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: consulting_hours_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.consulting_hours_id_seq OWNED BY public.consulting_hours.id;


--
-- Name: contact_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_histories (
    id bigint NOT NULL,
    contact_id bigint NOT NULL,
    event_type character varying(255),
    event_label text,
    event_meta jsonb DEFAULT '{}'::jsonb,
    event_datetime timestamp(0) without time zone,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    profile_id bigint
);


--
-- Name: TABLE contact_histories; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.contact_histories IS 'This table will hold all the contact history for a contact.';


--
-- Name: COLUMN contact_histories.event_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contact_histories.event_type IS 'The type of event that happened.';


--
-- Name: COLUMN contact_histories.event_label; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contact_histories.event_label IS 'The label of the event.';


--
-- Name: COLUMN contact_histories.event_meta; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contact_histories.event_meta IS 'The meta data for the event that happened.';


--
-- Name: COLUMN contact_histories.event_datetime; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contact_histories.event_datetime IS 'The date and time of the event that happened.';


--
-- Name: contact_histories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contact_histories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contact_histories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contact_histories_id_seq OWNED BY public.contact_histories.id;


--
-- Name: contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts (
    id bigint NOT NULL,
    name character varying(255),
    phone character varying(255) NOT NULL,
    bsp_status public.contact_provider_status_enum DEFAULT 'none'::public.contact_provider_status_enum NOT NULL,
    status public.contact_status_enum DEFAULT 'valid'::public.contact_status_enum NOT NULL,
    language_id bigint NOT NULL,
    optin_time timestamp(0) without time zone,
    optout_time timestamp(0) without time zone,
    last_message_at timestamp(0) without time zone,
    settings jsonb DEFAULT '{}'::jsonb,
    fields jsonb DEFAULT '{}'::jsonb,
    organization_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    last_communication_at timestamp(0) without time zone,
    optin_method character varying(255),
    optin_status boolean DEFAULT false,
    optin_message_id character varying(255),
    is_org_read boolean DEFAULT true,
    is_org_replied boolean DEFAULT true,
    is_contact_replied boolean DEFAULT true,
    last_message_number integer DEFAULT 0,
    optout_method character varying(255),
    active_profile_id bigint,
    first_message_number integer DEFAULT 1,
    contact_type character varying(255)
);


--
-- Name: TABLE contacts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.contacts IS 'Table for storing high level contact information provided by the user';


--
-- Name: COLUMN contacts.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.name IS 'User Name';


--
-- Name: COLUMN contacts.phone; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.phone IS 'Phone number of the user; primary point of identification';


--
-- Name: COLUMN contacts.bsp_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.bsp_status IS 'Whatsapp connection status; current options are : processing, valid, invalid & failed';


--
-- Name: COLUMN contacts.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.status IS 'Provider status; current options are :valid, invalid or blocked';


--
-- Name: COLUMN contacts.language_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.language_id IS 'Contact language for templates and other communications';


--
-- Name: COLUMN contacts.optin_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.optin_time IS 'Time when we recorded an opt-in from the user';


--
-- Name: COLUMN contacts.optout_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.optout_time IS 'Time when we recorded an opt-out from the user';


--
-- Name: COLUMN contacts.last_message_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.last_message_at IS 'Timestamp of most recent message sent by the user to ensure we can send a valid message to the user (< 24hr)';


--
-- Name: COLUMN contacts.settings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.settings IS 'Store the settings of the user as a map (which is a jsonb object in psql).
Preferences is one field in the settings (for now). The NGO can use this field to target
the user with messages based on their preferences. The user can select one or
more options from the preferences list. All settings are checkboxes or multi-select.
Merge this with fields, when we have type information
';


--
-- Name: COLUMN contacts.fields; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.fields IS 'Labels and values of the NGO generated fields for the user';


--
-- Name: COLUMN contacts.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.organization_id IS 'Unique organization ID';


--
-- Name: COLUMN contacts.inserted_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.inserted_at IS 'Time when the record entry was first made';


--
-- Name: COLUMN contacts.updated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.updated_at IS 'Time when the record entry was last updated';


--
-- Name: COLUMN contacts.optin_method; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.optin_method IS 'possible options include: URL, WhatsApp Message, QR Code, SMS, NGO';


--
-- Name: COLUMN contacts.optin_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.optin_status IS 'record if the contact has either opted or skipped the option';


--
-- Name: COLUMN contacts.optin_message_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.optin_message_id IS 'For whatsapp option, we''ll record the wa-message-id sent';


--
-- Name: COLUMN contacts.is_org_read; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.is_org_read IS 'Has a staff read the messages sent by this contact';


--
-- Name: COLUMN contacts.is_org_replied; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.is_org_replied IS 'Has a staff or flow replied to the messages sent by this contact';


--
-- Name: COLUMN contacts.is_contact_replied; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.is_contact_replied IS 'Has the contact replied to the messages sent by the system';


--
-- Name: COLUMN contacts.last_message_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.last_message_number IS 'The max message number recd or sent by this contact';


--
-- Name: COLUMN contacts.optout_method; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.optout_method IS 'possible options include: URL, WhatsApp Message, QR Code, SMS, NGO';


--
-- Name: COLUMN contacts.contact_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts.contact_type IS 'one of WABA, WA, WABA+WA';


--
-- Name: contacts_fields; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts_fields (
    id bigint NOT NULL,
    name character varying(255),
    shortcode character varying(255),
    value_type public.contact_field_value_type_enum,
    scope public.contact_field_scope_enum,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: contacts_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contacts_fields_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contacts_fields_id_seq OWNED BY public.contacts_fields.id;


--
-- Name: contacts_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts_groups (
    id bigint NOT NULL,
    contact_id bigint NOT NULL,
    group_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone DEFAULT '2021-01-01 00:00:00'::timestamp without time zone NOT NULL,
    updated_at timestamp(0) without time zone DEFAULT '2021-01-01 00:00:00'::timestamp without time zone NOT NULL
);


--
-- Name: contacts_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contacts_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contacts_groups_id_seq OWNED BY public.contacts_groups.id;


--
-- Name: contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contacts_id_seq OWNED BY public.contacts.id;


--
-- Name: contacts_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts_tags (
    id bigint NOT NULL,
    contact_id bigint NOT NULL,
    tag_id bigint NOT NULL,
    value character varying(255),
    organization_id bigint NOT NULL
);


--
-- Name: COLUMN contacts_tags.contact_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts_tags.contact_id IS 'Contact ID';


--
-- Name: COLUMN contacts_tags.tag_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts_tags.tag_id IS 'Tag ID';


--
-- Name: COLUMN contacts_tags.value; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts_tags.value IS 'Value of the tags, if applicable';


--
-- Name: contacts_tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contacts_tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contacts_tags_id_seq OWNED BY public.contacts_tags.id;


--
-- Name: contacts_wa_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts_wa_groups (
    id bigint NOT NULL,
    wa_group_id bigint NOT NULL,
    contact_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    is_admin boolean DEFAULT false,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN contacts_wa_groups.wa_group_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts_wa_groups.wa_group_id IS 'WA group the WhatsApp group is linked to';


--
-- Name: COLUMN contacts_wa_groups.contact_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts_wa_groups.contact_id IS 'contact id of the user who is added in the wa group';


--
-- Name: COLUMN contacts_wa_groups.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contacts_wa_groups.organization_id IS 'Unique organization ID';


--
-- Name: contacts_wa_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contacts_wa_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contacts_wa_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contacts_wa_groups_id_seq OWNED BY public.contacts_wa_groups.id;


--
-- Name: credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credentials (
    id bigint NOT NULL,
    keys jsonb DEFAULT '{}'::jsonb,
    secrets bytea,
    is_active boolean DEFAULT false,
    is_valid boolean DEFAULT true,
    provider_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.credentials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.credentials_id_seq OWNED BY public.credentials.id;


--
-- Name: extensions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.extensions (
    id bigint NOT NULL,
    name character varying(255),
    code text,
    module character varying(255),
    is_valid boolean DEFAULT false,
    is_active boolean DEFAULT true,
    organization_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: TABLE extensions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.extensions IS 'Lets store information and code for the extensions';


--
-- Name: COLUMN extensions.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.extensions.name IS 'The name of the extension';


--
-- Name: COLUMN extensions.code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.extensions.code IS 'The elixir source code for this module';


--
-- Name: COLUMN extensions.module; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.extensions.module IS 'The name of the module, useful when we want to unload it';


--
-- Name: COLUMN extensions.is_valid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.extensions.is_valid IS 'Does the code compile';


--
-- Name: extensions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.extensions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: extensions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.extensions_id_seq OWNED BY public.extensions.id;


--
-- Name: message_broadcast_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message_broadcast_contacts (
    id bigint NOT NULL,
    message_broadcast_id bigint NOT NULL,
    contact_id bigint NOT NULL,
    status character varying(255),
    organization_id bigint NOT NULL,
    processed_at timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    group_ids integer[] DEFAULT ARRAY[]::integer[]
);


--
-- Name: TABLE message_broadcast_contacts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.message_broadcast_contacts IS 'This table is populated when the user schedules a flow on a collection (or when we trigger a flow on a collection)';


--
-- Name: flow_broadcast_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flow_broadcast_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flow_broadcast_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flow_broadcast_contacts_id_seq OWNED BY public.message_broadcast_contacts.id;


--
-- Name: message_broadcasts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message_broadcasts (
    id bigint NOT NULL,
    flow_id bigint,
    group_id bigint NOT NULL,
    message_id bigint,
    user_id bigint,
    organization_id bigint NOT NULL,
    started_at timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
    completed_at timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    type character varying(255),
    message_params jsonb,
    default_results jsonb,
    group_ids integer[] DEFAULT ARRAY[]::integer[]
);


--
-- Name: TABLE message_broadcasts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.message_broadcasts IS 'This table is populated when the user schedules a flow on a collection (or when we trigger a flow on a collection)';


--
-- Name: COLUMN message_broadcasts.flow_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_broadcasts.flow_id IS 'Flow ID';


--
-- Name: COLUMN message_broadcasts.message_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_broadcasts.message_id IS 'If this message was sent to a group';


--
-- Name: COLUMN message_broadcasts.user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_broadcasts.user_id IS 'User who started the flow';


--
-- Name: COLUMN message_broadcasts.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_broadcasts.type IS 'type of the broadcast.';


--
-- Name: COLUMN message_broadcasts.message_params; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_broadcasts.message_params IS 'Messages attrs in case of message broadcast';


--
-- Name: COLUMN message_broadcasts.default_results; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_broadcasts.default_results IS 'Default results are required for the flow';


--
-- Name: flow_broadcasts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flow_broadcasts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flow_broadcasts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flow_broadcasts_id_seq OWNED BY public.message_broadcasts.id;


--
-- Name: flow_contexts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flow_contexts (
    id bigint NOT NULL,
    node_uuid uuid,
    flow_uuid uuid NOT NULL,
    contact_id bigint,
    flow_id bigint NOT NULL,
    results jsonb DEFAULT '{}'::jsonb,
    parent_id bigint,
    wakeup_at timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
    completed_at timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
    recent_inbound jsonb DEFAULT '[]'::jsonb,
    recent_outbound jsonb DEFAULT '[]'::jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    status character varying(255) DEFAULT 'published'::character varying,
    organization_id bigint NOT NULL,
    is_background_flow boolean DEFAULT false,
    group_message_id bigint,
    message_broadcast_id bigint,
    is_await_result boolean DEFAULT false,
    is_killed boolean DEFAULT false,
    profile_id bigint,
    reason character varying(255),
    wa_group_id bigint,
    channel character varying(255) DEFAULT 'whatsapp'::character varying NOT NULL
);


--
-- Name: COLUMN flow_contexts.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_contexts.status IS 'Status of the flow; either ''test'' or ''published''';


--
-- Name: COLUMN flow_contexts.is_background_flow; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_contexts.is_background_flow IS 'Adding wait time for the flows';


--
-- Name: COLUMN flow_contexts.group_message_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_contexts.group_message_id IS 'If this message was sent to a group, link the two';


--
-- Name: COLUMN flow_contexts.message_broadcast_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_contexts.message_broadcast_id IS 'If this message was sent to a group, link to the flow broadcast entry';


--
-- Name: COLUMN flow_contexts.is_await_result; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_contexts.is_await_result IS 'Is this flow context waiting for a result to be delivered via an API';


--
-- Name: COLUMN flow_contexts.is_killed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_contexts.is_killed IS 'Did we kill this flow?';


--
-- Name: COLUMN flow_contexts.wa_group_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_contexts.wa_group_id IS 'ID of WA group messages are sent/received from';


--
-- Name: COLUMN flow_contexts.channel; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_contexts.channel IS 'The channel (whatsapp, web, ...) of the message that triggered this flow context; propagated into the flow''s outbound sends so replies route back over the originating channel.';


--
-- Name: flow_contexts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flow_contexts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flow_contexts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flow_contexts_id_seq OWNED BY public.flow_contexts.id;


--
-- Name: flow_counts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flow_counts (
    id bigint NOT NULL,
    uuid uuid NOT NULL,
    destination_uuid uuid,
    flow_id bigint NOT NULL,
    flow_uuid uuid NOT NULL,
    type character varying(255),
    count integer DEFAULT 1,
    recent_messages jsonb[] DEFAULT ARRAY[]::jsonb[],
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    organization_id bigint NOT NULL
);


--
-- Name: flow_counts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flow_counts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flow_counts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flow_counts_id_seq OWNED BY public.flow_counts.id;


--
-- Name: flow_labels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flow_labels (
    id bigint NOT NULL,
    uuid uuid NOT NULL,
    name character varying(255),
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    type character varying(255)
);


--
-- Name: COLUMN flow_labels.uuid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_labels.uuid IS 'Unique ID for each flow label';


--
-- Name: COLUMN flow_labels.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_labels.name IS 'Name/tag of the flow label';


--
-- Name: COLUMN flow_labels.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_labels.organization_id IS 'Unique organization ID';


--
-- Name: COLUMN flow_labels.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_labels.type IS 'Flow label type for now can be flow or ticket';


--
-- Name: flow_labels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flow_labels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flow_labels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flow_labels_id_seq OWNED BY public.flow_labels.id;


--
-- Name: flow_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flow_results (
    id bigint NOT NULL,
    results jsonb DEFAULT '{}'::jsonb,
    contact_id bigint NOT NULL,
    flow_id bigint NOT NULL,
    flow_uuid uuid NOT NULL,
    flow_version integer DEFAULT 1 NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    flow_context_id bigint,
    profile_id bigint
);


--
-- Name: TABLE flow_results; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.flow_results IS 'Create a table to store the values for a specific flow at a specific point in time';


--
-- Name: COLUMN flow_results.results; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_results.results IS 'JSON object for storing the user responses';


--
-- Name: COLUMN flow_results.contact_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_results.contact_id IS 'Contact ID';


--
-- Name: COLUMN flow_results.flow_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_results.flow_id IS 'Flow ID';


--
-- Name: COLUMN flow_results.flow_uuid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_results.flow_uuid IS 'Unique ID of the flow; we store flows with both id and uuid, since flow editor always refers to a flow by its uuid ';


--
-- Name: COLUMN flow_results.flow_version; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_results.flow_version IS 'Which specific published version of the flow is being referred to';


--
-- Name: COLUMN flow_results.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_results.organization_id IS 'Unique organization ID';


--
-- Name: COLUMN flow_results.inserted_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_results.inserted_at IS 'Time when the record entry was first made';


--
-- Name: COLUMN flow_results.updated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_results.updated_at IS 'Time when the record entry was last updated';


--
-- Name: COLUMN flow_results.flow_context_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_results.flow_context_id IS 'Flow context that a contact is in with respect to a flow; this is not a foreign key';


--
-- Name: flow_results_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flow_results_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flow_results_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flow_results_id_seq OWNED BY public.flow_results.id;


--
-- Name: flow_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flow_revisions (
    id bigint NOT NULL,
    definition jsonb,
    flow_id bigint NOT NULL,
    revision_number integer DEFAULT 0,
    status character varying(255) DEFAULT 'draft'::character varying,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    version integer DEFAULT 0,
    organization_id bigint NOT NULL,
    user_id bigint
);


--
-- Name: COLUMN flow_revisions.flow_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_revisions.flow_id IS 'Flow ID';


--
-- Name: COLUMN flow_revisions.revision_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_revisions.revision_number IS 'Record of the revision made on the flow';


--
-- Name: COLUMN flow_revisions.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_revisions.status IS 'Status of flow revision draft or done';


--
-- Name: COLUMN flow_revisions.inserted_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_revisions.inserted_at IS 'Time when the record entry was first made';


--
-- Name: COLUMN flow_revisions.updated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_revisions.updated_at IS 'Time when the record entry was last updated';


--
-- Name: COLUMN flow_revisions.user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flow_revisions.user_id IS 'User ID of user who created this flow revision';


--
-- Name: flow_revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flow_revisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flow_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flow_revisions_id_seq OWNED BY public.flow_revisions.id;


--
-- Name: flow_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flow_roles (
    id bigint NOT NULL,
    role_id bigint NOT NULL,
    flow_id bigint NOT NULL,
    organization_id bigint NOT NULL
);


--
-- Name: flow_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flow_roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flow_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flow_roles_id_seq OWNED BY public.flow_roles.id;


--
-- Name: flows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flows (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    uuid uuid NOT NULL,
    version_number character varying(255) DEFAULT '13.1.0'::character varying,
    flow_type public.flow_type_enum DEFAULT 'message'::public.flow_type_enum NOT NULL,
    ignore_keywords boolean DEFAULT false,
    keywords character varying(255)[] DEFAULT ARRAY[]::character varying[],
    organization_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    respond_other boolean DEFAULT false,
    respond_no_response boolean DEFAULT false,
    is_active boolean DEFAULT true,
    is_background boolean DEFAULT false,
    is_pinned boolean DEFAULT false,
    tag_id bigint,
    description text,
    is_template boolean DEFAULT false,
    skip_validation boolean DEFAULT false,
    channels character varying(255)[] DEFAULT ARRAY['whatsapp'::character varying, 'web'::character varying] NOT NULL
);


--
-- Name: COLUMN flows.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.name IS 'Name of the created flow';


--
-- Name: COLUMN flows.uuid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.uuid IS 'Unique ID generated for each flow';


--
-- Name: COLUMN flows.version_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.version_number IS 'Flow version';


--
-- Name: COLUMN flows.flow_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.flow_type IS 'Type of flow; default - message';


--
-- Name: COLUMN flows.ignore_keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.ignore_keywords IS 'Enabling ignore keywords while in the flow';


--
-- Name: COLUMN flows.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.keywords IS 'List of keywords to trigger the flow';


--
-- Name: COLUMN flows.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.organization_id IS 'Unique organization ID';


--
-- Name: COLUMN flows.inserted_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.inserted_at IS 'Time when the record entry was first made';


--
-- Name: COLUMN flows.updated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.updated_at IS 'Time when the record entry was last updated';


--
-- Name: COLUMN flows.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.is_active IS 'Whether flows are currently in use or not';


--
-- Name: COLUMN flows.is_background; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.is_background IS 'Whether flows are background flows or not';


--
-- Name: COLUMN flows.is_pinned; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.is_pinned IS 'This is for showing the pinned flows at the top of flow screen';


--
-- Name: COLUMN flows.skip_validation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.skip_validation IS 'Allow users to skip validation for variables coming from resumeContact apis';


--
-- Name: COLUMN flows.channels; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.flows.channels IS 'Derived set of channels this flow reaches (contract §11.1): ["web"] once any node sends a blocks interactive template (monotonic — never cleared), ["whatsapp"] when any node is send_broadcast or a templated (HSM) send_msg, or the omnichannel default ["whatsapp", "web"]. Recomputed at Glific.Flows.maybe_update_flow_type_and_channels/2.';


--
-- Name: flows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flows_id_seq OWNED BY public.flows.id;


--
-- Name: gcs_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gcs_jobs (
    id bigint NOT NULL,
    message_media_id bigint,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    type character varying(255) DEFAULT 'incremental'::character varying
);


--
-- Name: COLUMN gcs_jobs.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.gcs_jobs.type IS 'can be incremental or unsynced. incremental for normal backup of files to GCS and unsynced to ensure the unsynced files are also backedup later time of day when traffic is low';


--
-- Name: gcs_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gcs_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gcs_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gcs_jobs_id_seq OWNED BY public.gcs_jobs.id;


--
-- Name: golden_qas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.golden_qas (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    dataset_id integer NOT NULL,
    duplication_factor integer DEFAULT 1,
    file_name character varying(255),
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: golden_qas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.golden_qas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: golden_qas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.golden_qas_id_seq OWNED BY public.golden_qas.id;


--
-- Name: group_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.group_roles (
    id bigint NOT NULL,
    role_id bigint NOT NULL,
    group_id bigint NOT NULL,
    organization_id bigint NOT NULL
);


--
-- Name: group_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.group_roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: group_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.group_roles_id_seq OWNED BY public.group_roles.id;


--
-- Name: groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.groups (
    id bigint NOT NULL,
    label character varying(255) NOT NULL,
    description text,
    is_restricted boolean DEFAULT false,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    last_communication_at timestamp(0) without time zone,
    last_message_number integer DEFAULT 0,
    group_type character varying(255)
);


--
-- Name: COLUMN groups.label; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.groups.label IS 'Label of the created groups';


--
-- Name: COLUMN groups.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.groups.description IS 'Description of the groups';


--
-- Name: COLUMN groups.is_restricted; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.groups.is_restricted IS 'Visibility status of conversations to the other groups';


--
-- Name: COLUMN groups.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.groups.organization_id IS 'Unique organization ID';


--
-- Name: COLUMN groups.last_communication_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.groups.last_communication_at IS 'Timestamp of the most recent communication';


--
-- Name: COLUMN groups.last_message_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.groups.last_message_number IS 'The max message number sent via this group';


--
-- Name: COLUMN groups.group_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.groups.group_type IS 'one of WABA, WA';


--
-- Name: groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.groups_id_seq OWNED BY public.groups.id;


--
-- Name: intents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.intents (
    id bigint NOT NULL,
    name character varying(255),
    organization_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: TABLE intents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.intents IS 'Lets store all the intents to utilize the nlp classifiers';


--
-- Name: COLUMN intents.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.intents.name IS 'The name of the Intent (for lookup)';


--
-- Name: COLUMN intents.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.intents.organization_id IS 'The master organization running this service';


--
-- Name: intents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.intents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: intents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.intents_id_seq OWNED BY public.intents.id;


--
-- Name: interactive_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.interactive_templates (
    id bigint NOT NULL,
    label character varying(255),
    type public.interactive_message_type_enum,
    interactive_content jsonb DEFAULT '[]'::jsonb,
    organization_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    translations jsonb DEFAULT '{}'::jsonb,
    language_id bigint DEFAULT 1 NOT NULL,
    send_with_title boolean DEFAULT true NOT NULL,
    tag_id bigint
);


--
-- Name: TABLE interactive_templates; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.interactive_templates IS 'Lets add interactive messages here';


--
-- Name: COLUMN interactive_templates.label; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.interactive_templates.label IS 'The label of the interactive message';


--
-- Name: COLUMN interactive_templates.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.interactive_templates.type IS 'The type of interactive message- quick_reply or list';


--
-- Name: COLUMN interactive_templates.interactive_content; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.interactive_templates.interactive_content IS 'Interactive content of the message stored in form of json';


--
-- Name: COLUMN interactive_templates.language_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.interactive_templates.language_id IS 'Language of the interactive message';


--
-- Name: COLUMN interactive_templates.send_with_title; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.interactive_templates.send_with_title IS 'Field to check if title needs to be send in the interactive message';


--
-- Name: interactive_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.interactive_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: interactive_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.interactive_templates_id_seq OWNED BY public.interactive_templates.id;


--
-- Name: invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoices (
    id bigint NOT NULL,
    customer_id character varying(255),
    invoice_id character varying(255) NOT NULL,
    start_date timestamp without time zone NOT NULL,
    end_date timestamp without time zone NOT NULL,
    status character varying(255) NOT NULL,
    amount integer NOT NULL,
    users integer DEFAULT 0,
    messages integer DEFAULT 0,
    consulting_hours integer DEFAULT 0,
    line_items jsonb DEFAULT '{}'::jsonb,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN invoices.invoice_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.invoice_id IS 'Stripe''s Invoice ID';


--
-- Name: COLUMN invoices.start_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.start_date IS 'The beginning date of the invoice';


--
-- Name: COLUMN invoices.end_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.end_date IS 'The end date of the invoice';


--
-- Name: COLUMN invoices.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.status IS 'The status of the invoice';


--
-- Name: COLUMN invoices.amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.amount IS 'The amount to be paid';


--
-- Name: COLUMN invoices.users; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.users IS 'The reported number of users in the last billing cycle';


--
-- Name: COLUMN invoices.messages; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.messages IS 'The reported number of messages sent in the last billing cycle';


--
-- Name: COLUMN invoices.consulting_hours; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.consulting_hours IS 'The reported consulting hours';


--
-- Name: COLUMN invoices.line_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.line_items IS 'A map of price-ids and their descriptions for line items in an invoice';


--
-- Name: COLUMN invoices.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.organization_id IS 'Related organization id';


--
-- Name: invoices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.invoices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: invoices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.invoices_id_seq OWNED BY public.invoices.id;


--
-- Name: issued_certificates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issued_certificates (
    id bigint NOT NULL,
    certificate_template_id bigint NOT NULL,
    contact_id bigint NOT NULL,
    gcs_url character varying(255),
    errors jsonb DEFAULT '{}'::jsonb,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN issued_certificates.certificate_template_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.issued_certificates.certificate_template_id IS 'Unique certificate template ID';


--
-- Name: COLUMN issued_certificates.contact_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.issued_certificates.contact_id IS 'Unique contact ID';


--
-- Name: COLUMN issued_certificates.gcs_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.issued_certificates.gcs_url IS 'GCS url of the final generated certificate';


--
-- Name: COLUMN issued_certificates.errors; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.issued_certificates.errors IS 'Error and reason during certificate generation';


--
-- Name: COLUMN issued_certificates.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.issued_certificates.organization_id IS 'Unique organization ID.';


--
-- Name: issued_certificates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.issued_certificates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: issued_certificates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.issued_certificates_id_seq OWNED BY public.issued_certificates.id;


--
-- Name: knowledge_base_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_base_versions (
    id bigint NOT NULL,
    version_number integer NOT NULL,
    llm_service_id character varying(255),
    kaapi_job_id character varying(255),
    files jsonb DEFAULT '{}'::jsonb,
    size bigint DEFAULT 0,
    status public.knowledge_base_status_enum DEFAULT 'in_progress'::public.knowledge_base_status_enum NOT NULL,
    organization_id bigint NOT NULL,
    knowledge_base_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN knowledge_base_versions.version_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.knowledge_base_versions.version_number IS 'Monotonically increasing version per knowledge base';


--
-- Name: COLUMN knowledge_base_versions.llm_service_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.knowledge_base_versions.llm_service_id IS 'Provider-side vector store identifier (if available)';


--
-- Name: COLUMN knowledge_base_versions.kaapi_job_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.knowledge_base_versions.kaapi_job_id IS 'Async job id returned by Kaapi during knowledge base creation';


--
-- Name: COLUMN knowledge_base_versions.files; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.knowledge_base_versions.files IS 'Files metadata for this knowledge base version';


--
-- Name: COLUMN knowledge_base_versions.size; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.knowledge_base_versions.size IS 'Size of this knowledge base version';


--
-- Name: COLUMN knowledge_base_versions.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.knowledge_base_versions.status IS 'Status of knowledge base creation - in_progress, completed, failed';


--
-- Name: COLUMN knowledge_base_versions.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.knowledge_base_versions.organization_id IS 'Unique organization ID.';


--
-- Name: COLUMN knowledge_base_versions.knowledge_base_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.knowledge_base_versions.knowledge_base_id IS 'Knowledge base this version belongs to';


--
-- Name: knowledge_base_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.knowledge_base_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: knowledge_base_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.knowledge_base_versions_id_seq OWNED BY public.knowledge_base_versions.id;


--
-- Name: knowledge_bases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_bases (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN knowledge_bases.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.knowledge_bases.name IS 'Name of the knowledge base';


--
-- Name: COLUMN knowledge_bases.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.knowledge_bases.organization_id IS 'Unique organization ID.';


--
-- Name: knowledge_bases_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.knowledge_bases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: knowledge_bases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.knowledge_bases_id_seq OWNED BY public.knowledge_bases.id;


--
-- Name: locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.locations (
    id bigint NOT NULL,
    contact_id bigint NOT NULL,
    message_id bigint,
    longitude double precision NOT NULL,
    latitude double precision NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    organization_id bigint NOT NULL,
    wa_message_id bigint
);


--
-- Name: COLUMN locations.contact_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.locations.contact_id IS 'Contact ID of the sender';


--
-- Name: COLUMN locations.message_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.locations.message_id IS 'Reference to the incoming message';


--
-- Name: COLUMN locations.longitude; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.locations.longitude IS 'Location longitude';


--
-- Name: COLUMN locations.latitude; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.locations.latitude IS 'Location latitude';


--
-- Name: COLUMN locations.wa_message_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.locations.wa_message_id IS 'ID of WA group';


--
-- Name: locations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.locations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: locations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.locations_id_seq OWNED BY public.locations.id;


--
-- Name: mail_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mail_logs (
    id bigint NOT NULL,
    category character varying(255) NOT NULL,
    status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    error character varying(255),
    content jsonb DEFAULT '{}'::jsonb,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN mail_logs.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mail_logs.organization_id IS 'Unique organization ID';


--
-- Name: mail_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mail_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mail_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mail_logs_id_seq OWNED BY public.mail_logs.id;


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id bigint NOT NULL,
    uuid uuid,
    body text,
    type public.message_type_enum,
    is_hsm boolean DEFAULT false,
    flow public.message_flow_enum,
    status public.message_status_enum DEFAULT 'enqueued'::public.message_status_enum NOT NULL,
    bsp_message_id text,
    bsp_status public.message_status_enum,
    errors jsonb,
    message_number bigint,
    sender_id bigint NOT NULL,
    receiver_id bigint NOT NULL,
    contact_id bigint NOT NULL,
    user_id bigint,
    media_id bigint,
    send_at timestamp(0) without time zone,
    sent_at timestamp(0) without time zone,
    organization_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    session_uuid uuid,
    flow_label character varying(255),
    flow_id bigint,
    group_id bigint,
    context_id text,
    context_message_id bigint,
    interactive_content jsonb DEFAULT '{}'::jsonb,
    group_message_id bigint,
    template_id bigint,
    interactive_template_id bigint,
    message_broadcast_id bigint,
    profile_id bigint,
    whatsapp_form_response_id bigint,
    channel character varying(255) DEFAULT 'whatsapp'::character varying NOT NULL
);


--
-- Name: TABLE messages; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.messages IS 'Record of all messages sent and/or received by the system';


--
-- Name: COLUMN messages.uuid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.uuid IS 'Uniquely generated message UUID, primarily needed for the flow editor';


--
-- Name: COLUMN messages.body; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.body IS 'Body of the message';


--
-- Name: COLUMN messages.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.type IS 'Type of the message; options are - text, audio, video, image, location, contact, file, sticker, quick_reply, list';


--
-- Name: COLUMN messages.is_hsm; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.is_hsm IS 'Field to check hsm message type';


--
-- Name: COLUMN messages.flow; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.flow IS 'Whether an inbound or an outbound message';


--
-- Name: COLUMN messages.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.status IS 'Delivery status of the message';


--
-- Name: COLUMN messages.bsp_message_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.bsp_message_id IS 'Whatsapp message ID';


--
-- Name: COLUMN messages.bsp_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.bsp_status IS 'Options : Sent, Delivered or Read';


--
-- Name: COLUMN messages.errors; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.errors IS 'Options : Sent, Delivered or Read';


--
-- Name: COLUMN messages.message_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.message_number IS 'Messaging number for a contact';


--
-- Name: COLUMN messages.sender_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.sender_id IS 'Contact number of the sender of the message';


--
-- Name: COLUMN messages.receiver_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.receiver_id IS 'Contact number of the receiver of the message';


--
-- Name: COLUMN messages.contact_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.contact_id IS 'Either sender contact number or receiver contact number; created to quickly let us know who the beneficiary is';


--
-- Name: COLUMN messages.user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.user_id IS 'User ID; this will be null for automated messages and messages received';


--
-- Name: COLUMN messages.media_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.media_id IS 'Message media ID';


--
-- Name: COLUMN messages.send_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.send_at IS 'Timestamp when message is scheduled to be sent';


--
-- Name: COLUMN messages.sent_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.sent_at IS 'Timestamp when message was sent from queue worker';


--
-- Name: COLUMN messages.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.organization_id IS 'Unique Organization ID';


--
-- Name: COLUMN messages.inserted_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.inserted_at IS 'Time when the record entry was first made';


--
-- Name: COLUMN messages.updated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.updated_at IS 'Time when the record entry was last updated';


--
-- Name: COLUMN messages.session_uuid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.session_uuid IS 'Unique session ID';


--
-- Name: COLUMN messages.flow_label; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.flow_label IS 'Tagged flow label for the message';


--
-- Name: COLUMN messages.flow_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.flow_id IS 'Flow with which the message is associated';


--
-- Name: COLUMN messages.group_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.group_id IS 'Group ID with which the message is associated';


--
-- Name: COLUMN messages.context_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.context_id IS 'If this message was a reply to a previous message, link the two';


--
-- Name: COLUMN messages.interactive_content; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.interactive_content IS 'the json data for interactive messages';


--
-- Name: COLUMN messages.group_message_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.group_message_id IS 'If this message was sent to a group, link the two';


--
-- Name: COLUMN messages.template_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.template_id IS 'reference for the HSM template';


--
-- Name: COLUMN messages.interactive_template_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.interactive_template_id IS 'reference for the interactive message template';


--
-- Name: COLUMN messages.message_broadcast_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.message_broadcast_id IS 'If this message was sent to a group, link to the flow broadcast entry';


--
-- Name: messages_conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages_conversations (
    id bigint NOT NULL,
    conversation_id text,
    deduction_type character varying(255),
    is_billable boolean DEFAULT false,
    message_id bigint,
    organization_id bigint NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN messages_conversations.message_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages_conversations.message_id IS 'reference for the message';


--
-- Name: COLUMN messages_conversations.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages_conversations.organization_id IS 'reference for the organization';


--
-- Name: messages_conversations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.messages_conversations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: messages_conversations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.messages_conversations_id_seq OWNED BY public.messages_conversations.id;


--
-- Name: messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.messages_id_seq OWNED BY public.messages.id;


--
-- Name: messages_media; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages_media (
    id bigint NOT NULL,
    url text NOT NULL,
    source_url text NOT NULL,
    thumbnail text,
    caption text,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    gcs_url text,
    organization_id bigint NOT NULL,
    content_type character varying(255),
    flow public.message_flow_enum,
    is_template_media boolean,
    gcs_error text
);


--
-- Name: COLUMN messages_media.url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages_media.url IS 'URL to be sent to BSP';


--
-- Name: COLUMN messages_media.source_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages_media.source_url IS 'Source URL';


--
-- Name: COLUMN messages_media.thumbnail; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages_media.thumbnail IS 'Thumbnail URL';


--
-- Name: COLUMN messages_media.caption; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages_media.caption IS 'Media caption';


--
-- Name: COLUMN messages_media.content_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages_media.content_type IS 'Content Type for the media message sent by WABA';


--
-- Name: COLUMN messages_media.gcs_error; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages_media.gcs_error IS 'Failure reason while trying to sync to gcs';


--
-- Name: messages_media_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.messages_media_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: messages_media_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.messages_media_id_seq OWNED BY public.messages_media.id;


--
-- Name: messages_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages_tags (
    id bigint NOT NULL,
    message_id bigint NOT NULL,
    tag_id bigint NOT NULL,
    value character varying(255),
    organization_id bigint NOT NULL
);


--
-- Name: COLUMN messages_tags.message_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages_tags.message_id IS 'Message ID';


--
-- Name: COLUMN messages_tags.tag_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages_tags.tag_id IS 'Tags ID';


--
-- Name: COLUMN messages_tags.value; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages_tags.value IS 'Value of the tags, if applicable';


--
-- Name: messages_tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.messages_tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: messages_tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.messages_tags_id_seq OWNED BY public.messages_tags.id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id bigint NOT NULL,
    entity jsonb DEFAULT '{}'::jsonb,
    category character varying(255),
    message text,
    severity text DEFAULT 'Error'::text,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    is_read boolean DEFAULT false
);


--
-- Name: COLUMN notifications.entity; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.notifications.entity IS 'A map of objects that are involved in this notification';


--
-- Name: COLUMN notifications.category; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.notifications.category IS 'The category that this falls under: Flow, Message, BigQuery, etc';


--
-- Name: COLUMN notifications.message; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.notifications.message IS 'The specific error message that caused this notification';


--
-- Name: COLUMN notifications.severity; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.notifications.severity IS 'The severity level. We''ll include a few info notifications';


--
-- Name: COLUMN notifications.is_read; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.notifications.is_read IS 'Has the user read the notifications.';


--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notifications_id_seq OWNED BY public.notifications.id;


--
-- Name: organization_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_data (
    id bigint NOT NULL,
    key character varying(255) NOT NULL,
    description character varying(255),
    "json" jsonb DEFAULT '{}'::jsonb,
    text text,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN organization_data.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organization_data.organization_id IS 'Unique organization ID';


--
-- Name: organization_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.organization_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organization_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.organization_data_id_seq OWNED BY public.organization_data.id;


--
-- Name: organization_eval_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_eval_requests (
    id bigint NOT NULL,
    status character varying(255) DEFAULT 'requested'::character varying NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: organization_eval_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.organization_eval_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organization_eval_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.organization_eval_requests_id_seq OWNED BY public.organization_eval_requests.id;


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    shortcode character varying(255) NOT NULL,
    email character varying(255),
    bsp_id bigint NOT NULL,
    default_language_id bigint NOT NULL,
    active_language_ids integer[] DEFAULT ARRAY[]::integer[],
    contact_id integer,
    out_of_office jsonb,
    is_active boolean DEFAULT true,
    timezone character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    session_limit integer DEFAULT 60,
    organization_id bigint,
    signature_phrase bytea,
    last_communication_at timestamp(0) without time zone,
    is_approved boolean DEFAULT false,
    fields jsonb DEFAULT '{}'::jsonb,
    status public.organization_status_enum DEFAULT 'inactive'::public.organization_status_enum,
    newcontact_flow_id bigint,
    is_suspended boolean DEFAULT false,
    suspended_until timestamp(0) without time zone,
    regx_flow jsonb,
    optin_flow_id bigint,
    team_emails jsonb,
    parent_org character varying,
    setting jsonb DEFAULT '{}'::jsonb,
    is_trial_org boolean DEFAULT false,
    trial_expiration_date timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
    deleted_at timestamp(0) without time zone
);


--
-- Name: TABLE organizations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.organizations IS 'Organizations on the platform';


--
-- Name: COLUMN organizations.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.name IS 'Organization name';


--
-- Name: COLUMN organizations.shortcode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.shortcode IS 'Organization shortcode';


--
-- Name: COLUMN organizations.email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.email IS 'Email provided by the organization for registration';


--
-- Name: COLUMN organizations.default_language_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.default_language_id IS 'Default language for the organization';


--
-- Name: COLUMN organizations.active_language_ids; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.active_language_ids IS 'List of active languages used by the organization from the supported languages';


--
-- Name: COLUMN organizations.contact_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.contact_id IS 'Contact ID of the organization that can send messages out';


--
-- Name: COLUMN organizations.out_of_office; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.out_of_office IS 'JSON object of the out of office information';


--
-- Name: COLUMN organizations.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.is_active IS 'Whether an organization''s service is active or not';


--
-- Name: COLUMN organizations.timezone; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.timezone IS 'Organization''s operational timezone';


--
-- Name: COLUMN organizations.session_limit; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.session_limit IS 'Add a session limit field to decide length of sessions in minutes';


--
-- Name: COLUMN organizations.last_communication_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.last_communication_at IS 'Timestamp of the last communication made';


--
-- Name: COLUMN organizations.is_approved; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.is_approved IS 'Manual approval of an organization to trigger onboarding workflow';


--
-- Name: COLUMN organizations.fields; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.fields IS 'Labels and values of the NGO generated global fields';


--
-- Name: COLUMN organizations.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.status IS 'organization status to define different states of the organizations';


--
-- Name: COLUMN organizations.newcontact_flow_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.newcontact_flow_id IS 'Flow which will trigger when new contact joins the bot';


--
-- Name: COLUMN organizations.is_suspended; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.is_suspended IS 'Organizations that have been temporarily suspended from sending messages';


--
-- Name: COLUMN organizations.suspended_until; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.suspended_until IS 'Till when does the suspension last, this is typically the start of the next day in the org''s timezone';


--
-- Name: COLUMN organizations.regx_flow; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.regx_flow IS 'Regx flow config for the organization';


--
-- Name: COLUMN organizations.optin_flow_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.optin_flow_id IS 'Flow which will trigger for contact to optin';


--
-- Name: COLUMN organizations.is_trial_org; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.is_trial_org IS 'whether this is a trial org';


--
-- Name: COLUMN organizations.trial_expiration_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.trial_expiration_date IS 'When the trial period for this org ends';


--
-- Name: organizations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.organizations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organizations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.organizations_id_seq OWNED BY public.organizations.id;


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id bigint NOT NULL,
    name character varying(255),
    contact_id bigint NOT NULL,
    language_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    fields jsonb,
    type character varying(255),
    is_active boolean DEFAULT true,
    is_default boolean DEFAULT false
);


--
-- Name: COLUMN profiles.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.name IS 'Name of the profile';


--
-- Name: COLUMN profiles.contact_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.contact_id IS 'reference for the contact';


--
-- Name: COLUMN profiles.language_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.language_id IS 'reference for the language';


--
-- Name: COLUMN profiles.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.organization_id IS 'reference for the organization';


--
-- Name: COLUMN profiles.fields; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.fields IS 'Labels and values of the NGO generated fields for the contact which is synced in/out to contact fields';


--
-- Name: COLUMN profiles.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.type IS 'This is optional and depends on NGO usecase';


--
-- Name: COLUMN profiles.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.is_active IS 'if the profile is deactivated then the value would be false else true';


--
-- Name: profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.profiles_id_seq OWNED BY public.profiles.id;


--
-- Name: prompt_generation_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prompt_generation_requests (
    id bigint NOT NULL,
    inputs jsonb NOT NULL,
    generated_prompt text,
    status character varying(255) DEFAULT 'in_progress'::character varying NOT NULL,
    request_id character varying(255) NOT NULL,
    error_message text,
    organization_id bigint NOT NULL,
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: COLUMN prompt_generation_requests.inputs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prompt_generation_requests.inputs IS 'The 9 NGO answers used to generate the prompt (keyed by field name)';


--
-- Name: COLUMN prompt_generation_requests.generated_prompt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prompt_generation_requests.generated_prompt IS 'The LLM-generated system prompt; nil until status is ready';


--
-- Name: COLUMN prompt_generation_requests.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prompt_generation_requests.status IS 'Lifecycle status: in_progress | ready | failed';


--
-- Name: COLUMN prompt_generation_requests.request_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prompt_generation_requests.request_id IS 'Correlation id we send to Kaapi in request_metadata; echoed back in the callback metadata';


--
-- Name: COLUMN prompt_generation_requests.error_message; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prompt_generation_requests.error_message IS 'Error detail from Kaapi callback when status is failed';


--
-- Name: COLUMN prompt_generation_requests.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prompt_generation_requests.organization_id IS 'Organization scope';


--
-- Name: COLUMN prompt_generation_requests.user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prompt_generation_requests.user_id IS 'User who initiated the generation request; nullable';


--
-- Name: prompt_generation_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.prompt_generation_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: prompt_generation_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.prompt_generation_requests_id_seq OWNED BY public.prompt_generation_requests.id;


--
-- Name: registrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.registrations (
    id bigint NOT NULL,
    org_details jsonb,
    platform_details jsonb,
    billing_frequency character varying(255) DEFAULT 'monthly'::character varying,
    finance_poc jsonb,
    submitter jsonb,
    signing_authority jsonb,
    has_submitted boolean DEFAULT false,
    has_confirmed boolean DEFAULT false,
    ip_address character varying(255),
    terms_agreed boolean DEFAULT false,
    support_staff_account boolean DEFAULT true,
    organization_id bigint NOT NULL,
    notion_page_id character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    is_disputed boolean,
    erp_page_id character varying(255)
);


--
-- Name: COLUMN registrations.org_details; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.org_details IS 'Details about the organization.';


--
-- Name: COLUMN registrations.platform_details; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.platform_details IS 'Details about the Gupshup platform.';


--
-- Name: COLUMN registrations.billing_frequency; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.billing_frequency IS 'Frequency of billing one of yearly, monthly, quarterly';


--
-- Name: COLUMN registrations.finance_poc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.finance_poc IS 'Billing details.';


--
-- Name: COLUMN registrations.submitter; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.submitter IS 'Details of the submitter';


--
-- Name: COLUMN registrations.signing_authority; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.signing_authority IS 'Details of the signing authority.';


--
-- Name: COLUMN registrations.has_submitted; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.has_submitted IS 'Flag indicating if the registration has been submitted.';


--
-- Name: COLUMN registrations.has_confirmed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.has_confirmed IS 'Flag indicating if the applicant have confirmed the registration via email';


--
-- Name: COLUMN registrations.ip_address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.ip_address IS 'IP address of the submitter';


--
-- Name: COLUMN registrations.terms_agreed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.terms_agreed IS 'Flag indicating if the user agreed or disagreed with the T&C';


--
-- Name: COLUMN registrations.support_staff_account; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.support_staff_account IS 'Flag indicating if user agrees to create a support staff account';


--
-- Name: COLUMN registrations.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.organization_id IS 'Unique organization ID.';


--
-- Name: COLUMN registrations.notion_page_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.notion_page_id IS 'ID of the org''s row in notion''s onboarding-list database';


--
-- Name: COLUMN registrations.is_disputed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.is_disputed IS 'if the user disputed the T&C';


--
-- Name: COLUMN registrations.erp_page_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.registrations.erp_page_id IS 'ID of the org''s row in ERP''s customer-list database';


--
-- Name: registrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.registrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: registrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.registrations_id_seq OWNED BY public.registrations.id;


--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permissions (
    id bigint NOT NULL,
    role_id bigint NOT NULL,
    permission_id bigint NOT NULL,
    organization_id bigint NOT NULL
);


--
-- Name: role_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.role_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: role_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.role_permissions_id_seq OWNED BY public.role_permissions.id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id bigint NOT NULL,
    label character varying(255),
    description character varying(255),
    is_reserved boolean DEFAULT false NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN roles.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.roles.organization_id IS 'Unique organization ID';


--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- Name: saas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saas (
    id bigint NOT NULL,
    name character varying(255),
    organization_id bigint,
    phone character varying(255),
    stripe_ids jsonb DEFAULT '[]'::jsonb,
    tax_rates jsonb DEFAULT '[]'::jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    email character varying(255),
    isv_credentials jsonb DEFAULT '{}'::jsonb
);


--
-- Name: TABLE saas; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.saas IS 'Lets store all the meta data we need to drive the SaaS platform in this table';


--
-- Name: COLUMN saas.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.saas.name IS 'The name of the SaaS (for lookup)';


--
-- Name: COLUMN saas.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.saas.organization_id IS 'The master organization running this service';


--
-- Name: COLUMN saas.phone; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.saas.phone IS 'Phone number for the SaaS admin account';


--
-- Name: COLUMN saas.stripe_ids; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.saas.stripe_ids IS 'All the stripe subscriptions IDS, no more config';


--
-- Name: COLUMN saas.tax_rates; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.saas.tax_rates IS 'All the stripe tax rates';


--
-- Name: COLUMN saas.email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.saas.email IS 'Primary email address for the saas team.';


--
-- Name: saas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.saas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: saas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.saas_id_seq OWNED BY public.saas.id;


--
-- Name: saved_searches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saved_searches (
    id bigint NOT NULL,
    label character varying(255) NOT NULL,
    args jsonb,
    shortcode character varying(255),
    is_reserved boolean DEFAULT false,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN saved_searches.args; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.saved_searches.args IS 'Search arguments used by the user, saved as a jsonb blob';


--
-- Name: COLUMN saved_searches.shortcode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.saved_searches.shortcode IS 'Shortcode of the saved searches to display in UI';


--
-- Name: COLUMN saved_searches.is_reserved; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.saved_searches.is_reserved IS 'Is this a predefined system object?';


--
-- Name: COLUMN saved_searches.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.saved_searches.organization_id IS 'Unique organization ID';


--
-- Name: saved_searches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.saved_searches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: saved_searches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.saved_searches_id_seq OWNED BY public.saved_searches.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: schema_seeds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_seeds (
    version bigint NOT NULL,
    tenant character varying(255) DEFAULT 'main'::character varying NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: session_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.session_templates (
    id bigint NOT NULL,
    uuid uuid NOT NULL,
    label character varying(255) NOT NULL,
    body text,
    type public.message_type_enum,
    is_reserved boolean DEFAULT false,
    is_active boolean DEFAULT true,
    is_source boolean DEFAULT false,
    shortcode character varying(255),
    is_hsm boolean DEFAULT false,
    number_parameters integer,
    language_id bigint NOT NULL,
    parent_id bigint,
    message_media_id bigint,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    translations jsonb DEFAULT '{}'::jsonb,
    status character varying(255),
    category character varying(255),
    example text,
    has_buttons boolean DEFAULT false,
    button_type public.template_button_type_enum,
    buttons jsonb DEFAULT '[]'::jsonb,
    bsp_id character varying(255),
    reason character varying(255),
    tag_id bigint,
    quality character varying(255),
    allow_template_category_change boolean DEFAULT true,
    footer character varying(255)
);


--
-- Name: COLUMN session_templates.uuid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.uuid IS 'The template UUID, primarily needed for flow editor';


--
-- Name: COLUMN session_templates.label; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.label IS 'Message label';


--
-- Name: COLUMN session_templates.body; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.body IS 'Body of the message';


--
-- Name: COLUMN session_templates.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.type IS 'Type of the message; options are - text, audio, video, image, location, contact, file, sticker';


--
-- Name: COLUMN session_templates.is_reserved; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.is_reserved IS 'Whether the particular template is a predefined system object or not';


--
-- Name: COLUMN session_templates.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.is_active IS 'Whether this value is currently in use';


--
-- Name: COLUMN session_templates.is_source; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.is_source IS 'Is this the original root message';


--
-- Name: COLUMN session_templates.shortcode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.shortcode IS 'Message shortcode';


--
-- Name: COLUMN session_templates.is_hsm; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.is_hsm IS 'Field to check hsm message type';


--
-- Name: COLUMN session_templates.number_parameters; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.number_parameters IS 'Number of parameters in HSM message';


--
-- Name: COLUMN session_templates.language_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.language_id IS 'Language of the message';


--
-- Name: COLUMN session_templates.parent_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.parent_id IS 'Parent Message ID; all child messages point to the root message';


--
-- Name: COLUMN session_templates.message_media_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.message_media_id IS 'Message media IDs';


--
-- Name: COLUMN session_templates.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.organization_id IS 'Unique Organization ID';


--
-- Name: COLUMN session_templates.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.status IS 'Whatsapp status of the HSM template';


--
-- Name: COLUMN session_templates.category; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.category IS 'Whatsapp HSM category';


--
-- Name: COLUMN session_templates.example; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.example IS 'HSM example with parameters';


--
-- Name: COLUMN session_templates.has_buttons; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.has_buttons IS 'Does template have buttons';


--
-- Name: COLUMN session_templates.button_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.button_type IS 'type of button QUICK_REPLY or CALL_TO_ACTION';


--
-- Name: COLUMN session_templates.reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.session_templates.reason IS 'reason for template being rejected';


--
-- Name: session_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.session_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: session_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.session_templates_id_seq OWNED BY public.session_templates.id;


--
-- Name: sheets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sheets (
    id bigint NOT NULL,
    label character varying(255) NOT NULL,
    url character varying(255) NOT NULL,
    is_active boolean DEFAULT true,
    last_synced_at timestamp(0) without time zone DEFAULT now(),
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    sheet_data_count integer,
    type character varying(255),
    auto_sync boolean DEFAULT false,
    sync_status public.sheet_sync_status_enum DEFAULT 'success'::public.sheet_sync_status_enum,
    failure_reason text
);


--
-- Name: COLUMN sheets.label; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sheets.label IS 'Label of the sheet';


--
-- Name: COLUMN sheets.url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sheets.url IS 'Sheet URL along with gid';


--
-- Name: COLUMN sheets.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sheets.is_active IS 'Whether the sheet is currently used by organization or not';


--
-- Name: COLUMN sheets.last_synced_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sheets.last_synced_at IS 'Time when the sheet was last synced at';


--
-- Name: COLUMN sheets.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sheets.type IS 'Google sheet type which can be READ, WRITE or ALL';


--
-- Name: COLUMN sheets.auto_sync; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sheets.auto_sync IS 'Auto Sync Sheets data in some interval';


--
-- Name: COLUMN sheets.sync_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sheets.sync_status IS 'Status of the sync operation';


--
-- Name: sheets_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sheets_data (
    id bigint NOT NULL,
    key character varying(255) NOT NULL,
    row_data jsonb DEFAULT '{}'::jsonb,
    last_synced_at timestamp(0) without time zone DEFAULT now(),
    sheet_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN sheets_data.key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sheets_data.key IS 'Row''s Key of the referenced sheet';


--
-- Name: COLUMN sheets_data.row_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sheets_data.row_data IS 'Sheet''s row level data saved from last sync';


--
-- Name: COLUMN sheets_data.last_synced_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sheets_data.last_synced_at IS 'Time when the sheet data was last synced at';


--
-- Name: sheets_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sheets_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sheets_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sheets_data_id_seq OWNED BY public.sheets_data.id;


--
-- Name: sheets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sheets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sheets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sheets_id_seq OWNED BY public.sheets.id;


--
-- Name: stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stats (
    id bigint NOT NULL,
    contacts integer,
    active integer,
    optin integer,
    optout integer,
    messages integer,
    inbound integer,
    outbound integer,
    hsm integer,
    flows_started integer,
    flows_completed integer,
    users integer,
    period character varying(255),
    date date,
    hour integer,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    conversations integer DEFAULT 0
);


--
-- Name: COLUMN stats.contacts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.contacts IS 'Total number of contacts in the system. This is the only absolute number in non-summary records';


--
-- Name: COLUMN stats.active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.active IS 'Total number of active contacts';


--
-- Name: COLUMN stats.optin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.optin IS 'Number of opted in contacts';


--
-- Name: COLUMN stats.optout; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.optout IS 'Number of opted out contacts';


--
-- Name: COLUMN stats.messages; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.messages IS 'Total number of messages';


--
-- Name: COLUMN stats.inbound; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.inbound IS 'Total number of inbound messages';


--
-- Name: COLUMN stats.outbound; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.outbound IS 'Total number of outbound messages';


--
-- Name: COLUMN stats.hsm; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.hsm IS 'Total number of HSM messages (outbound only)';


--
-- Name: COLUMN stats.flows_started; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.flows_started IS 'Total number of flows started today';


--
-- Name: COLUMN stats.flows_completed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.flows_completed IS 'Total number of flows completed today';


--
-- Name: COLUMN stats.users; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.users IS 'Total number of users active';


--
-- Name: COLUMN stats.period; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.period IS 'The period for this record: hour, day, week, month, summary';


--
-- Name: COLUMN stats.date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.date IS 'All stats are measured with respect to UTC time, to keep things timezone agnostic';


--
-- Name: COLUMN stats.hour; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stats.hour IS 'The hour that this record represents, 0..23, only for PERIOD: hour';


--
-- Name: stats_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stats_id_seq OWNED BY public.stats.id;


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tags (
    id bigint NOT NULL,
    label character varying(255) NOT NULL,
    shortcode character varying(255) NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    is_reserved boolean DEFAULT false,
    ancestors bigint[],
    is_value boolean DEFAULT false,
    keywords character varying(255)[],
    color_code character varying(255) DEFAULT '#0C976D'::character varying,
    language_id bigint NOT NULL,
    parent_id bigint,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN tags.label; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tags.label IS 'Labels of the created tags';


--
-- Name: COLUMN tags.shortcode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tags.shortcode IS 'Shortcodes of the created tags, if any';


--
-- Name: COLUMN tags.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tags.description IS 'Optional description for the tags';


--
-- Name: COLUMN tags.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tags.is_active IS 'Whether tags are currently in use or not';


--
-- Name: COLUMN tags.is_reserved; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tags.is_reserved IS 'Whether the particular tag is a predefined system object or not';


--
-- Name: COLUMN tags.is_value; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tags.is_value IS 'Does this tag potentially have a value associated with it
If so, this value will be stored in the join tables. This is applicable only
for Numeric and Keyword message tags for now, but also include contact tags to
keep them in sync
';


--
-- Name: COLUMN tags.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tags.keywords IS 'Keywords associated with the tags';


--
-- Name: COLUMN tags.color_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tags.color_code IS 'Define a color code to associate it with a tag';


--
-- Name: COLUMN tags.language_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tags.language_id IS 'Foreign key for the language';


--
-- Name: COLUMN tags.parent_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tags.parent_id IS 'All child tags point to the parent tag, this allows for organizing tags as needed';


--
-- Name: COLUMN tags.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tags.organization_id IS 'Foreign key to organization restricting scope of this table to an organization only';


--
-- Name: tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tags_id_seq OWNED BY public.tags.id;


--
-- Name: templates_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.templates_tags (
    id bigint NOT NULL,
    template_id bigint NOT NULL,
    tag_id bigint NOT NULL,
    value character varying(255),
    organization_id bigint NOT NULL
);


--
-- Name: templates_tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.templates_tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: templates_tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.templates_tags_id_seq OWNED BY public.templates_tags.id;


--
-- Name: tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tickets (
    id bigint NOT NULL,
    body text,
    topic text,
    status text,
    remarks text,
    contact_id bigint NOT NULL,
    user_id bigint,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    message_number integer,
    flow_id bigint
);


--
-- Name: COLUMN tickets.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tickets.status IS 'Status of this ticket: Open or Closed';


--
-- Name: COLUMN tickets.remarks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tickets.remarks IS 'Closing remarks for the ticket';


--
-- Name: COLUMN tickets.flow_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tickets.flow_id IS 'Flow ID';


--
-- Name: tickets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tickets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tickets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tickets_id_seq OWNED BY public.tickets.id;


--
-- Name: trackers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trackers (
    id bigint NOT NULL,
    period character varying(255),
    date date,
    counts jsonb,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN trackers.period; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.trackers.period IS 'The period for this record: day or month';


--
-- Name: COLUMN trackers.date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.trackers.date IS 'All events are measured with respect to UTC time, to keep things timezone agnostic';


--
-- Name: COLUMN trackers.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.trackers.organization_id IS 'reference for the organization';


--
-- Name: trackers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trackers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trackers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trackers_id_seq OWNED BY public.trackers.id;


--
-- Name: translate_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.translate_logs (
    id bigint NOT NULL,
    text text,
    translated_text text,
    translation_engine character varying(255),
    source_language character varying(255),
    destination_language character varying(255),
    status boolean,
    error character varying(255),
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN translate_logs.text; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.translate_logs.text IS 'Original text to be translated.';


--
-- Name: COLUMN translate_logs.translated_text; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.translate_logs.translated_text IS 'Translated text.';


--
-- Name: COLUMN translate_logs.translation_engine; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.translate_logs.translation_engine IS 'Translation engine used: either Google Translate or Open AI.';


--
-- Name: COLUMN translate_logs.source_language; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.translate_logs.source_language IS 'Language of the original text to be translated.';


--
-- Name: COLUMN translate_logs.destination_language; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.translate_logs.destination_language IS 'Language of the translated text.';


--
-- Name: COLUMN translate_logs.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.translate_logs.status IS 'Flag indicating whether the translation was successful or not.';


--
-- Name: COLUMN translate_logs.error; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.translate_logs.error IS 'Error received from API';


--
-- Name: COLUMN translate_logs.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.translate_logs.organization_id IS 'Unique organization ID.';


--
-- Name: translate_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.translate_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: translate_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.translate_logs_id_seq OWNED BY public.translate_logs.id;


--
-- Name: trial_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trial_users (
    id bigint NOT NULL,
    username character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    phone character varying(255) NOT NULL,
    organization_name character varying(255) NOT NULL,
    otp_entered boolean DEFAULT false NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: trial_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trial_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trial_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trial_users_id_seq OWNED BY public.trial_users.id;


--
-- Name: trigger_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trigger_logs (
    id bigint NOT NULL,
    trigger_id bigint NOT NULL,
    started_at timestamp(0) without time zone NOT NULL,
    flow_context_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: trigger_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trigger_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trigger_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trigger_logs_id_seq OWNED BY public.trigger_logs.id;


--
-- Name: trigger_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trigger_roles (
    id bigint NOT NULL,
    role_id bigint NOT NULL,
    trigger_id bigint NOT NULL,
    organization_id bigint NOT NULL
);


--
-- Name: trigger_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trigger_roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trigger_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trigger_roles_id_seq OWNED BY public.trigger_roles.id;


--
-- Name: triggers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.triggers (
    id bigint NOT NULL,
    name character varying(255),
    trigger_type character varying(255) DEFAULT 'scheduled'::character varying,
    group_id bigint,
    flow_id bigint,
    start_at timestamp(0) without time zone NOT NULL,
    end_date date,
    last_trigger_at timestamp(0) without time zone,
    next_trigger_at timestamp(0) without time zone,
    is_repeating boolean DEFAULT false,
    frequency character varying(255)[] DEFAULT ARRAY[]::character varying[],
    days integer[] DEFAULT ARRAY[]::integer[],
    is_active boolean DEFAULT true,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    hours integer[] DEFAULT ARRAY[]::integer[],
    group_ids integer[] DEFAULT ARRAY[]::integer[],
    group_type character varying(255)
);


--
-- Name: COLUMN triggers.group_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.triggers.group_type IS 'one of WABA, WA';


--
-- Name: triggers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.triggers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: triggers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.triggers_id_seq OWNED BY public.triggers.id;


--
-- Name: user_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_jobs (
    id bigint NOT NULL,
    status character varying(255) DEFAULT 'pending'::character varying,
    type character varying(255),
    total_tasks integer,
    tasks_done integer,
    all_tasks_created boolean DEFAULT false,
    organization_id bigint NOT NULL,
    errors jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN user_jobs.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_jobs.status IS 'Job status: failed/pending/success';


--
-- Name: COLUMN user_jobs.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_jobs.type IS 'Type of job, e.g., contact_import';


--
-- Name: COLUMN user_jobs.total_tasks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_jobs.total_tasks IS 'Total number of tasks for this job';


--
-- Name: COLUMN user_jobs.tasks_done; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_jobs.tasks_done IS 'Number of tasks completed for this job';


--
-- Name: COLUMN user_jobs.all_tasks_created; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_jobs.all_tasks_created IS 'Specifies whether all tasks created';


--
-- Name: COLUMN user_jobs.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_jobs.organization_id IS 'Unique organization ID.';


--
-- Name: COLUMN user_jobs.errors; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_jobs.errors IS 'Details of any errors that occurred during the job';


--
-- Name: user_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_jobs_id_seq OWNED BY public.user_jobs.id;


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_roles (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    role_id bigint NOT NULL,
    organization_id bigint NOT NULL
);


--
-- Name: COLUMN user_roles.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_roles.organization_id IS 'Unique organization ID';


--
-- Name: user_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_roles_id_seq OWNED BY public.user_roles.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    phone character varying(255) NOT NULL,
    password_hash character varying(255),
    name character varying(255),
    roles public.user_roles_enum[] DEFAULT ARRAY['none'::public.user_roles_enum],
    contact_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    is_restricted boolean DEFAULT false,
    last_login_at timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
    last_login_from character varying(255) DEFAULT NULL::character varying,
    language_id bigint,
    upload_contacts boolean DEFAULT false,
    confirmed_at timestamp(0) without time zone,
    email character varying(255),
    consent_for_updates boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN users.phone; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.phone IS 'User''s Contact number';


--
-- Name: COLUMN users.password_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.password_hash IS 'Password Hash';


--
-- Name: COLUMN users.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.name IS 'User Name';


--
-- Name: COLUMN users.roles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.roles IS 'User Role';


--
-- Name: COLUMN users.contact_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.contact_id IS 'Contact ID of the User';


--
-- Name: COLUMN users.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.organization_id IS 'Unique organization ID';


--
-- Name: COLUMN users.language_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.language_id IS 'Foreign key for the language';


--
-- Name: COLUMN users.upload_contacts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.upload_contacts IS 'If user can upload the contacts.';


--
-- Name: users_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users_groups (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    group_id bigint NOT NULL,
    organization_id bigint NOT NULL
);


--
-- Name: users_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_groups_id_seq OWNED BY public.users_groups.id;


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: users_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users_tokens (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    token bytea NOT NULL,
    context character varying(255) NOT NULL,
    sent_to character varying(255),
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL
);


--
-- Name: users_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_tokens_id_seq OWNED BY public.users_tokens.id;


--
-- Name: versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.versions (
    id bigint NOT NULL,
    patch bytea NOT NULL,
    entity_id integer NOT NULL,
    entity_schema character varying(255) NOT NULL,
    action character varying(255) NOT NULL,
    recorded_at timestamp(0) without time zone NOT NULL,
    rollback boolean DEFAULT false NOT NULL,
    user_id bigint,
    organization_id bigint
);


--
-- Name: COLUMN versions.patch; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.versions.patch IS 'The patch in Erlang External Term Format';


--
-- Name: COLUMN versions.entity_schema; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.versions.entity_schema IS 'name of the table the entity is in';


--
-- Name: COLUMN versions.action; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.versions.action IS 'type of the action that has happened to the entity (created, updated, deleted)';


--
-- Name: COLUMN versions.recorded_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.versions.recorded_at IS 'when has this happened';


--
-- Name: COLUMN versions.rollback; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.versions.rollback IS 'was this change part of a rollback?';


--
-- Name: COLUMN versions.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.versions.organization_id IS 'Unique organization ID.';


--
-- Name: versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.versions_id_seq OWNED BY public.versions.id;


--
-- Name: wa_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wa_groups (
    id bigint NOT NULL,
    label character varying(255) NOT NULL,
    wa_managed_phone_id bigint NOT NULL,
    bsp_id character varying(255),
    organization_id bigint NOT NULL,
    last_communication_at timestamp(0) without time zone,
    last_message_number integer DEFAULT 0,
    is_org_read boolean DEFAULT true,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    fields jsonb DEFAULT '{}'::jsonb
);


--
-- Name: COLUMN wa_groups.label; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups.label IS 'Label of the WhatsApp group';


--
-- Name: COLUMN wa_groups.wa_managed_phone_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups.wa_managed_phone_id IS 'WA managed phone the WhatsApp group is linked to';


--
-- Name: COLUMN wa_groups.bsp_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups.bsp_id IS 'Unique id of WhatsApp group provided by BSP';


--
-- Name: COLUMN wa_groups.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups.organization_id IS 'Unique organization ID';


--
-- Name: COLUMN wa_groups.last_communication_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups.last_communication_at IS 'Timestamp of the most recent communication in wa_group';


--
-- Name: COLUMN wa_groups.last_message_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups.last_message_number IS 'The max message number recd or sent by this contact in wa_group';


--
-- Name: COLUMN wa_groups.is_org_read; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups.is_org_read IS 'Has a staff read the messages sent in this wa_group';


--
-- Name: COLUMN wa_groups.fields; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups.fields IS 'Labels and values of the NGO generated fields for the WA group';


--
-- Name: wa_groups_collections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wa_groups_collections (
    id bigint NOT NULL,
    wa_group_id bigint NOT NULL,
    group_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN wa_groups_collections.wa_group_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups_collections.wa_group_id IS 'WA group the WhatsApp group is linked to';


--
-- Name: COLUMN wa_groups_collections.group_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups_collections.group_id IS 'group the WhatsApp group is linked to';


--
-- Name: wa_groups_collections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wa_groups_collections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wa_groups_collections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wa_groups_collections_id_seq OWNED BY public.wa_groups_collections.id;


--
-- Name: wa_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wa_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wa_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wa_groups_id_seq OWNED BY public.wa_groups.id;


--
-- Name: wa_groups_phones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wa_groups_phones (
    id bigint NOT NULL,
    wa_group_id bigint NOT NULL,
    wa_managed_phone_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN wa_groups_phones.wa_group_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups_phones.wa_group_id IS 'WA group this membership belongs to';


--
-- Name: COLUMN wa_groups_phones.wa_managed_phone_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups_phones.wa_managed_phone_id IS 'Maytapi-linked phone that is a member of the group';


--
-- Name: COLUMN wa_groups_phones.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups_phones.organization_id IS 'Organization scope';


--
-- Name: COLUMN wa_groups_phones.is_primary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups_phones.is_primary IS 'Marks the primary phone for outbound sends to this group';


--
-- Name: COLUMN wa_groups_phones.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_groups_phones.is_active IS 'False when the phone is no longer a member of the group on WhatsApp';


--
-- Name: wa_groups_phones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wa_groups_phones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wa_groups_phones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wa_groups_phones_id_seq OWNED BY public.wa_groups_phones.id;


--
-- Name: wa_managed_phones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wa_managed_phones (
    id bigint NOT NULL,
    label character varying(255),
    phone character varying(255) NOT NULL,
    phone_id integer,
    product_id character varying(255),
    organization_id bigint NOT NULL,
    contact_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    status character varying(255),
    last_status_checked_at timestamp without time zone
);


--
-- Name: COLUMN wa_managed_phones.label; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_managed_phones.label IS 'Identification for this phone';


--
-- Name: COLUMN wa_managed_phones.contact_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_managed_phones.contact_id IS 'contact id wa_managed_phone';


--
-- Name: COLUMN wa_managed_phones.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_managed_phones.status IS 'status of the phone connected to Maytapi to see whether it is active or not';


--
-- Name: COLUMN wa_managed_phones.last_status_checked_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_managed_phones.last_status_checked_at IS 'When the phone''s status was last reconciled against Maytapi (webhook or poll)';


--
-- Name: wa_managed_phones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wa_managed_phones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wa_managed_phones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wa_managed_phones_id_seq OWNED BY public.wa_managed_phones.id;


--
-- Name: wa_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wa_messages (
    id bigint NOT NULL,
    uuid uuid,
    body text,
    type public.message_type_enum,
    flow public.message_flow_enum,
    status public.message_status_enum DEFAULT 'enqueued'::public.message_status_enum NOT NULL,
    bsp_status public.message_status_enum NOT NULL,
    bsp_id character varying(255),
    errors jsonb,
    message_number bigint,
    contact_id bigint NOT NULL,
    wa_managed_phone_id bigint,
    media_id bigint,
    send_at timestamp(0) without time zone,
    sent_at timestamp(0) without time zone,
    group_id bigint,
    wa_group_id bigint,
    organization_id bigint NOT NULL,
    is_dm boolean DEFAULT false,
    context_id text,
    context_message_id bigint,
    message_broadcast_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    flow_label character varying(255),
    poll_content jsonb DEFAULT '{}'::jsonb,
    poll_id bigint
);


--
-- Name: COLUMN wa_messages.uuid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.uuid IS 'Uniquely generated message UUID, primarily needed for the flow editor';


--
-- Name: COLUMN wa_messages.body; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.body IS 'Body of the message';


--
-- Name: COLUMN wa_messages.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.type IS 'Type of the message; options are - text, audio, video, image, location, contact, file, sticker';


--
-- Name: COLUMN wa_messages.flow; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.flow IS 'Whether an inbound or an outbound message';


--
-- Name: COLUMN wa_messages.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.status IS 'Delivery status of the message';


--
-- Name: COLUMN wa_messages.bsp_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.bsp_status IS 'Whatsapp connection status; current options are : processing, valid, invalid & failed';


--
-- Name: COLUMN wa_messages.bsp_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.bsp_id IS 'Message ID from provider';


--
-- Name: COLUMN wa_messages.errors; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.errors IS 'Options : Sent, Delivered or Read';


--
-- Name: COLUMN wa_messages.message_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.message_number IS 'Messaging number for a WhatsApp group';


--
-- Name: COLUMN wa_messages.contact_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.contact_id IS 'contact id of beneficiary if the message is received or contact id of WA managed phone if the message is send';


--
-- Name: COLUMN wa_messages.wa_managed_phone_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.wa_managed_phone_id IS 'WA managed phone id of the number linked to Maytapi account';


--
-- Name: COLUMN wa_messages.media_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.media_id IS 'Message media ID';


--
-- Name: COLUMN wa_messages.send_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.send_at IS 'Timestamp when message is scheduled to be sent';


--
-- Name: COLUMN wa_messages.sent_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.sent_at IS 'Timestamp when message was sent from queue worker';


--
-- Name: COLUMN wa_messages.group_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.group_id IS 'ID of group, message is sent to';


--
-- Name: COLUMN wa_messages.wa_group_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.wa_group_id IS 'ID of WA group,  message is sent/received from';


--
-- Name: COLUMN wa_messages.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.organization_id IS 'Unique organization ID';


--
-- Name: COLUMN wa_messages.is_dm; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.is_dm IS 'Flag to check if the message is Group Message or DM';


--
-- Name: COLUMN wa_messages.context_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.context_id IS 'ID of the message context';


--
-- Name: COLUMN wa_messages.flow_label; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.flow_label IS 'Tagged flow label for WA messages';


--
-- Name: COLUMN wa_messages.poll_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_messages.poll_id IS 'Reference for the Whatsapp groups poll';


--
-- Name: wa_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wa_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wa_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wa_messages_id_seq OWNED BY public.wa_messages.id;


--
-- Name: wa_polls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wa_polls (
    id bigint NOT NULL,
    uuid uuid NOT NULL,
    label character varying(255) NOT NULL,
    poll_content jsonb DEFAULT '{}'::jsonb,
    allow_multiple_answer boolean DEFAULT false,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN wa_polls.uuid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_polls.uuid IS 'Uniquely generated message UUID, primarily needed for using in a flow webhook';


--
-- Name: COLUMN wa_polls.label; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_polls.label IS 'Title of the whatsapp poll';


--
-- Name: COLUMN wa_polls.poll_content; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_polls.poll_content IS 'poll content';


--
-- Name: COLUMN wa_polls.allow_multiple_answer; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_polls.allow_multiple_answer IS 'if users can select multiple answers in a WhatsApp poll or not';


--
-- Name: COLUMN wa_polls.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_polls.organization_id IS 'Unique organization ID.';


--
-- Name: wa_polls_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wa_polls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wa_polls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wa_polls_id_seq OWNED BY public.wa_polls.id;


--
-- Name: wa_reactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wa_reactions (
    id bigint NOT NULL,
    bsp_id character varying(255) NOT NULL,
    reaction text NOT NULL,
    wa_message_id bigint NOT NULL,
    contact_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: COLUMN wa_reactions.bsp_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_reactions.bsp_id IS 'Message ID from provider';


--
-- Name: COLUMN wa_reactions.reaction; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_reactions.reaction IS 'Reaction';


--
-- Name: COLUMN wa_reactions.wa_message_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_reactions.wa_message_id IS 'Unique WA Message ID';


--
-- Name: COLUMN wa_reactions.contact_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_reactions.contact_id IS 'Unique contact ID';


--
-- Name: COLUMN wa_reactions.organization_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wa_reactions.organization_id IS 'Unique organization ID.';


--
-- Name: wa_reactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wa_reactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wa_reactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wa_reactions_id_seq OWNED BY public.wa_reactions.id;


--
-- Name: webhook_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_logs (
    id bigint NOT NULL,
    url text NOT NULL,
    method text NOT NULL,
    request_headers jsonb DEFAULT '{}'::jsonb,
    request_json jsonb DEFAULT '{}'::jsonb,
    response_json jsonb DEFAULT '{}'::jsonb,
    status_code integer,
    error text,
    flow_id bigint NOT NULL,
    contact_id integer,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    wa_group_id bigint,
    flow_context_id bigint
);


--
-- Name: webhook_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.webhook_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: webhook_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.webhook_logs_id_seq OWNED BY public.webhook_logs.id;


--
-- Name: whatsapp_form_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_form_revisions (
    id bigint NOT NULL,
    revision_number integer NOT NULL,
    definition jsonb NOT NULL,
    whatsapp_form_id bigint NOT NULL,
    user_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: whatsapp_form_revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.whatsapp_form_revisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whatsapp_form_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.whatsapp_form_revisions_id_seq OWNED BY public.whatsapp_form_revisions.id;


--
-- Name: whatsapp_forms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_forms (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    meta_flow_id character varying(255) NOT NULL,
    status public.whatsapp_forms_status_enum DEFAULT 'draft'::public.whatsapp_forms_status_enum NOT NULL,
    definition jsonb DEFAULT '{}'::jsonb,
    categories public.whatsapp_forms_category_enum[] DEFAULT ARRAY[]::public.whatsapp_forms_category_enum[],
    organization_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    revision_id bigint,
    sheet_id bigint
);


--
-- Name: COLUMN whatsapp_forms.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.whatsapp_forms.name IS 'Name of the form';


--
-- Name: COLUMN whatsapp_forms.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.whatsapp_forms.description IS 'Description of the form';


--
-- Name: COLUMN whatsapp_forms.meta_flow_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.whatsapp_forms.meta_flow_id IS 'ID of the form received from Meta';


--
-- Name: COLUMN whatsapp_forms.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.whatsapp_forms.status IS 'Current status of the form';


--
-- Name: COLUMN whatsapp_forms.definition; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.whatsapp_forms.definition IS 'JSON of the form';


--
-- Name: COLUMN whatsapp_forms.categories; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.whatsapp_forms.categories IS 'Categories of the form';


--
-- Name: whatsapp_forms_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.whatsapp_forms_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whatsapp_forms_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.whatsapp_forms_id_seq OWNED BY public.whatsapp_forms.id;


--
-- Name: whatsapp_forms_responses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_forms_responses (
    id bigint NOT NULL,
    raw_response jsonb DEFAULT '{}'::jsonb,
    submitted_at timestamp without time zone NOT NULL,
    contact_id bigint NOT NULL,
    whatsapp_form_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: COLUMN whatsapp_forms_responses.raw_response; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.whatsapp_forms_responses.raw_response IS 'JSON of the response';


--
-- Name: COLUMN whatsapp_forms_responses.submitted_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.whatsapp_forms_responses.submitted_at IS 'Timestamp of the submission';


--
-- Name: whatsapp_forms_responses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.whatsapp_forms_responses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whatsapp_forms_responses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.whatsapp_forms_responses_id_seq OWNED BY public.whatsapp_forms_responses.id;


--
-- Name: fun_with_flags_toggles id; Type: DEFAULT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.fun_with_flags_toggles ALTER COLUMN id SET DEFAULT nextval('global.fun_with_flags_toggles_id_seq'::regclass);


--
-- Name: languages id; Type: DEFAULT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.languages ALTER COLUMN id SET DEFAULT nextval('global.languages_id_seq'::regclass);


--
-- Name: oban_jobs id; Type: DEFAULT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.oban_jobs ALTER COLUMN id SET DEFAULT nextval('global.oban_jobs_id_seq'::regclass);


--
-- Name: permissions id; Type: DEFAULT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.permissions ALTER COLUMN id SET DEFAULT nextval('global.permissions_id_seq'::regclass);


--
-- Name: providers id; Type: DEFAULT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.providers ALTER COLUMN id SET DEFAULT nextval('global.providers_id_seq'::regclass);


--
-- Name: ai_evaluations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_evaluations ALTER COLUMN id SET DEFAULT nextval('public.ai_evaluations_id_seq'::regclass);


--
-- Name: ask_glific_conversations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ask_glific_conversations ALTER COLUMN id SET DEFAULT nextval('public.ask_glific_conversations_id_seq'::regclass);


--
-- Name: assistant_config_version_knowledge_base_versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_config_version_knowledge_base_versions ALTER COLUMN id SET DEFAULT nextval('public.assistant_config_version_knowledge_base_versions_id_seq'::regclass);


--
-- Name: assistant_config_versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_config_versions ALTER COLUMN id SET DEFAULT nextval('public.assistant_config_versions_id_seq'::regclass);


--
-- Name: assistants id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistants ALTER COLUMN id SET DEFAULT nextval('public.assistants_id_seq'::regclass);


--
-- Name: bigquery_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bigquery_jobs ALTER COLUMN id SET DEFAULT nextval('public.bigquery_jobs_id_seq'::regclass);


--
-- Name: billings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billings ALTER COLUMN id SET DEFAULT nextval('public.billings_id_seq'::regclass);


--
-- Name: certificate_templates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificate_templates ALTER COLUMN id SET DEFAULT nextval('public.certificate_templates_id_seq'::regclass);


--
-- Name: consulting_hours id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consulting_hours ALTER COLUMN id SET DEFAULT nextval('public.consulting_hours_id_seq'::regclass);


--
-- Name: contact_histories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_histories ALTER COLUMN id SET DEFAULT nextval('public.contact_histories_id_seq'::regclass);


--
-- Name: contacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts ALTER COLUMN id SET DEFAULT nextval('public.contacts_id_seq'::regclass);


--
-- Name: contacts_fields id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_fields ALTER COLUMN id SET DEFAULT nextval('public.contacts_fields_id_seq'::regclass);


--
-- Name: contacts_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_groups ALTER COLUMN id SET DEFAULT nextval('public.contacts_groups_id_seq'::regclass);


--
-- Name: contacts_tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_tags ALTER COLUMN id SET DEFAULT nextval('public.contacts_tags_id_seq'::regclass);


--
-- Name: contacts_wa_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_wa_groups ALTER COLUMN id SET DEFAULT nextval('public.contacts_wa_groups_id_seq'::regclass);


--
-- Name: credentials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credentials ALTER COLUMN id SET DEFAULT nextval('public.credentials_id_seq'::regclass);


--
-- Name: extensions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extensions ALTER COLUMN id SET DEFAULT nextval('public.extensions_id_seq'::regclass);


--
-- Name: flow_contexts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_contexts ALTER COLUMN id SET DEFAULT nextval('public.flow_contexts_id_seq'::regclass);


--
-- Name: flow_counts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_counts ALTER COLUMN id SET DEFAULT nextval('public.flow_counts_id_seq'::regclass);


--
-- Name: flow_labels id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_labels ALTER COLUMN id SET DEFAULT nextval('public.flow_labels_id_seq'::regclass);


--
-- Name: flow_results id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_results ALTER COLUMN id SET DEFAULT nextval('public.flow_results_id_seq'::regclass);


--
-- Name: flow_revisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_revisions ALTER COLUMN id SET DEFAULT nextval('public.flow_revisions_id_seq'::regclass);


--
-- Name: flow_roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_roles ALTER COLUMN id SET DEFAULT nextval('public.flow_roles_id_seq'::regclass);


--
-- Name: flows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flows ALTER COLUMN id SET DEFAULT nextval('public.flows_id_seq'::regclass);


--
-- Name: gcs_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gcs_jobs ALTER COLUMN id SET DEFAULT nextval('public.gcs_jobs_id_seq'::regclass);


--
-- Name: golden_qas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_qas ALTER COLUMN id SET DEFAULT nextval('public.golden_qas_id_seq'::regclass);


--
-- Name: group_roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_roles ALTER COLUMN id SET DEFAULT nextval('public.group_roles_id_seq'::regclass);


--
-- Name: groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.groups ALTER COLUMN id SET DEFAULT nextval('public.groups_id_seq'::regclass);


--
-- Name: intents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intents ALTER COLUMN id SET DEFAULT nextval('public.intents_id_seq'::regclass);


--
-- Name: interactive_templates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.interactive_templates ALTER COLUMN id SET DEFAULT nextval('public.interactive_templates_id_seq'::regclass);


--
-- Name: invoices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices ALTER COLUMN id SET DEFAULT nextval('public.invoices_id_seq'::regclass);


--
-- Name: issued_certificates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issued_certificates ALTER COLUMN id SET DEFAULT nextval('public.issued_certificates_id_seq'::regclass);


--
-- Name: knowledge_base_versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base_versions ALTER COLUMN id SET DEFAULT nextval('public.knowledge_base_versions_id_seq'::regclass);


--
-- Name: knowledge_bases id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_bases ALTER COLUMN id SET DEFAULT nextval('public.knowledge_bases_id_seq'::regclass);


--
-- Name: locations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.locations ALTER COLUMN id SET DEFAULT nextval('public.locations_id_seq'::regclass);


--
-- Name: mail_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mail_logs ALTER COLUMN id SET DEFAULT nextval('public.mail_logs_id_seq'::regclass);


--
-- Name: message_broadcast_contacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_broadcast_contacts ALTER COLUMN id SET DEFAULT nextval('public.flow_broadcast_contacts_id_seq'::regclass);


--
-- Name: message_broadcasts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_broadcasts ALTER COLUMN id SET DEFAULT nextval('public.flow_broadcasts_id_seq'::regclass);


--
-- Name: messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages ALTER COLUMN id SET DEFAULT nextval('public.messages_id_seq'::regclass);


--
-- Name: messages_conversations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages_conversations ALTER COLUMN id SET DEFAULT nextval('public.messages_conversations_id_seq'::regclass);


--
-- Name: messages_media id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages_media ALTER COLUMN id SET DEFAULT nextval('public.messages_media_id_seq'::regclass);


--
-- Name: messages_tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages_tags ALTER COLUMN id SET DEFAULT nextval('public.messages_tags_id_seq'::regclass);


--
-- Name: notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications ALTER COLUMN id SET DEFAULT nextval('public.notifications_id_seq'::regclass);


--
-- Name: organization_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_data ALTER COLUMN id SET DEFAULT nextval('public.organization_data_id_seq'::regclass);


--
-- Name: organization_eval_requests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_eval_requests ALTER COLUMN id SET DEFAULT nextval('public.organization_eval_requests_id_seq'::regclass);


--
-- Name: organizations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations ALTER COLUMN id SET DEFAULT nextval('public.organizations_id_seq'::regclass);


--
-- Name: profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles ALTER COLUMN id SET DEFAULT nextval('public.profiles_id_seq'::regclass);


--
-- Name: prompt_generation_requests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_generation_requests ALTER COLUMN id SET DEFAULT nextval('public.prompt_generation_requests_id_seq'::regclass);


--
-- Name: registrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.registrations ALTER COLUMN id SET DEFAULT nextval('public.registrations_id_seq'::regclass);


--
-- Name: role_permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions ALTER COLUMN id SET DEFAULT nextval('public.role_permissions_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: saas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saas ALTER COLUMN id SET DEFAULT nextval('public.saas_id_seq'::regclass);


--
-- Name: saved_searches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_searches ALTER COLUMN id SET DEFAULT nextval('public.saved_searches_id_seq'::regclass);


--
-- Name: session_templates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_templates ALTER COLUMN id SET DEFAULT nextval('public.session_templates_id_seq'::regclass);


--
-- Name: sheets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sheets ALTER COLUMN id SET DEFAULT nextval('public.sheets_id_seq'::regclass);


--
-- Name: sheets_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sheets_data ALTER COLUMN id SET DEFAULT nextval('public.sheets_data_id_seq'::regclass);


--
-- Name: stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stats ALTER COLUMN id SET DEFAULT nextval('public.stats_id_seq'::regclass);


--
-- Name: tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags ALTER COLUMN id SET DEFAULT nextval('public.tags_id_seq'::regclass);


--
-- Name: templates_tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.templates_tags ALTER COLUMN id SET DEFAULT nextval('public.templates_tags_id_seq'::regclass);


--
-- Name: tickets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets ALTER COLUMN id SET DEFAULT nextval('public.tickets_id_seq'::regclass);


--
-- Name: trackers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trackers ALTER COLUMN id SET DEFAULT nextval('public.trackers_id_seq'::regclass);


--
-- Name: translate_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.translate_logs ALTER COLUMN id SET DEFAULT nextval('public.translate_logs_id_seq'::regclass);


--
-- Name: trial_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trial_users ALTER COLUMN id SET DEFAULT nextval('public.trial_users_id_seq'::regclass);


--
-- Name: trigger_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger_logs ALTER COLUMN id SET DEFAULT nextval('public.trigger_logs_id_seq'::regclass);


--
-- Name: trigger_roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger_roles ALTER COLUMN id SET DEFAULT nextval('public.trigger_roles_id_seq'::regclass);


--
-- Name: triggers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.triggers ALTER COLUMN id SET DEFAULT nextval('public.triggers_id_seq'::regclass);


--
-- Name: user_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_jobs ALTER COLUMN id SET DEFAULT nextval('public.user_jobs_id_seq'::regclass);


--
-- Name: user_roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles ALTER COLUMN id SET DEFAULT nextval('public.user_roles_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: users_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_groups ALTER COLUMN id SET DEFAULT nextval('public.users_groups_id_seq'::regclass);


--
-- Name: users_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_tokens ALTER COLUMN id SET DEFAULT nextval('public.users_tokens_id_seq'::regclass);


--
-- Name: versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions ALTER COLUMN id SET DEFAULT nextval('public.versions_id_seq'::regclass);


--
-- Name: wa_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups ALTER COLUMN id SET DEFAULT nextval('public.wa_groups_id_seq'::regclass);


--
-- Name: wa_groups_collections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups_collections ALTER COLUMN id SET DEFAULT nextval('public.wa_groups_collections_id_seq'::regclass);


--
-- Name: wa_groups_phones id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups_phones ALTER COLUMN id SET DEFAULT nextval('public.wa_groups_phones_id_seq'::regclass);


--
-- Name: wa_managed_phones id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_managed_phones ALTER COLUMN id SET DEFAULT nextval('public.wa_managed_phones_id_seq'::regclass);


--
-- Name: wa_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_messages ALTER COLUMN id SET DEFAULT nextval('public.wa_messages_id_seq'::regclass);


--
-- Name: wa_polls id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_polls ALTER COLUMN id SET DEFAULT nextval('public.wa_polls_id_seq'::regclass);


--
-- Name: wa_reactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_reactions ALTER COLUMN id SET DEFAULT nextval('public.wa_reactions_id_seq'::regclass);


--
-- Name: webhook_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_logs ALTER COLUMN id SET DEFAULT nextval('public.webhook_logs_id_seq'::regclass);


--
-- Name: whatsapp_form_revisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_form_revisions ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_form_revisions_id_seq'::regclass);


--
-- Name: whatsapp_forms id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_forms ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_forms_id_seq'::regclass);


--
-- Name: whatsapp_forms_responses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_forms_responses ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_forms_responses_id_seq'::regclass);


--
-- Name: fun_with_flags_toggles fun_with_flags_toggles_pkey; Type: CONSTRAINT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.fun_with_flags_toggles
    ADD CONSTRAINT fun_with_flags_toggles_pkey PRIMARY KEY (id);


--
-- Name: languages languages_pkey; Type: CONSTRAINT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.languages
    ADD CONSTRAINT languages_pkey PRIMARY KEY (id);


--
-- Name: oban_jobs non_negative_priority; Type: CHECK CONSTRAINT; Schema: global; Owner: -
--

ALTER TABLE global.oban_jobs
    ADD CONSTRAINT non_negative_priority CHECK ((priority >= 0)) NOT VALID;


--
-- Name: oban_crons oban_crons_pkey; Type: CONSTRAINT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.oban_crons
    ADD CONSTRAINT oban_crons_pkey PRIMARY KEY (name);


--
-- Name: oban_jobs oban_jobs_pkey; Type: CONSTRAINT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.oban_jobs
    ADD CONSTRAINT oban_jobs_pkey PRIMARY KEY (id);


--
-- Name: oban_peers oban_peers_pkey; Type: CONSTRAINT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.oban_peers
    ADD CONSTRAINT oban_peers_pkey PRIMARY KEY (name);


--
-- Name: oban_producers oban_producers_pkey; Type: CONSTRAINT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.oban_producers
    ADD CONSTRAINT oban_producers_pkey PRIMARY KEY (uuid);


--
-- Name: oban_queues oban_queues_pkey; Type: CONSTRAINT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.oban_queues
    ADD CONSTRAINT oban_queues_pkey PRIMARY KEY (name);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);


--
-- Name: providers providers_pkey; Type: CONSTRAINT; Schema: global; Owner: -
--

ALTER TABLE ONLY global.providers
    ADD CONSTRAINT providers_pkey PRIMARY KEY (id);


--
-- Name: ai_evaluations ai_evaluations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_evaluations
    ADD CONSTRAINT ai_evaluations_pkey PRIMARY KEY (id);


--
-- Name: ask_glific_conversations ask_glific_conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ask_glific_conversations
    ADD CONSTRAINT ask_glific_conversations_pkey PRIMARY KEY (id);


--
-- Name: assistant_config_version_knowledge_base_versions assistant_config_version_knowledge_base_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_config_version_knowledge_base_versions
    ADD CONSTRAINT assistant_config_version_knowledge_base_versions_pkey PRIMARY KEY (id);


--
-- Name: assistant_config_versions assistant_config_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_config_versions
    ADD CONSTRAINT assistant_config_versions_pkey PRIMARY KEY (id);


--
-- Name: assistants assistants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistants
    ADD CONSTRAINT assistants_pkey PRIMARY KEY (id);


--
-- Name: bigquery_jobs bigquery_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bigquery_jobs
    ADD CONSTRAINT bigquery_jobs_pkey PRIMARY KEY (id);


--
-- Name: billings billings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billings
    ADD CONSTRAINT billings_pkey PRIMARY KEY (id);


--
-- Name: certificate_templates certificate_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificate_templates
    ADD CONSTRAINT certificate_templates_pkey PRIMARY KEY (id);


--
-- Name: consulting_hours consulting_hours_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consulting_hours
    ADD CONSTRAINT consulting_hours_pkey PRIMARY KEY (id);


--
-- Name: contact_histories contact_histories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_histories
    ADD CONSTRAINT contact_histories_pkey PRIMARY KEY (id);


--
-- Name: contacts_fields contacts_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_fields
    ADD CONSTRAINT contacts_fields_pkey PRIMARY KEY (id);


--
-- Name: contacts_groups contacts_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_groups
    ADD CONSTRAINT contacts_groups_pkey PRIMARY KEY (id);


--
-- Name: contacts contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_pkey PRIMARY KEY (id);


--
-- Name: contacts_tags contacts_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_tags
    ADD CONSTRAINT contacts_tags_pkey PRIMARY KEY (id);


--
-- Name: contacts_wa_groups contacts_wa_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_wa_groups
    ADD CONSTRAINT contacts_wa_groups_pkey PRIMARY KEY (id);


--
-- Name: credentials credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_pkey PRIMARY KEY (id);


--
-- Name: extensions extensions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extensions
    ADD CONSTRAINT extensions_pkey PRIMARY KEY (id);


--
-- Name: message_broadcast_contacts flow_broadcast_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_broadcast_contacts
    ADD CONSTRAINT flow_broadcast_contacts_pkey PRIMARY KEY (id);


--
-- Name: message_broadcasts flow_broadcasts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_broadcasts
    ADD CONSTRAINT flow_broadcasts_pkey PRIMARY KEY (id);


--
-- Name: flow_contexts flow_contexts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_contexts
    ADD CONSTRAINT flow_contexts_pkey PRIMARY KEY (id);


--
-- Name: flow_counts flow_counts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_counts
    ADD CONSTRAINT flow_counts_pkey PRIMARY KEY (id);


--
-- Name: flow_labels flow_labels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_labels
    ADD CONSTRAINT flow_labels_pkey PRIMARY KEY (id);


--
-- Name: flow_results flow_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_results
    ADD CONSTRAINT flow_results_pkey PRIMARY KEY (id);


--
-- Name: flow_revisions flow_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_revisions
    ADD CONSTRAINT flow_revisions_pkey PRIMARY KEY (id);


--
-- Name: flow_roles flow_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_roles
    ADD CONSTRAINT flow_roles_pkey PRIMARY KEY (id);


--
-- Name: flows flows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flows
    ADD CONSTRAINT flows_pkey PRIMARY KEY (id);


--
-- Name: gcs_jobs gcs_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gcs_jobs
    ADD CONSTRAINT gcs_jobs_pkey PRIMARY KEY (id);


--
-- Name: golden_qas golden_qas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_qas
    ADD CONSTRAINT golden_qas_pkey PRIMARY KEY (id);


--
-- Name: group_roles group_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_roles
    ADD CONSTRAINT group_roles_pkey PRIMARY KEY (id);


--
-- Name: groups groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (id);


--
-- Name: intents intents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intents
    ADD CONSTRAINT intents_pkey PRIMARY KEY (id);


--
-- Name: interactive_templates interactive_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.interactive_templates
    ADD CONSTRAINT interactive_templates_pkey PRIMARY KEY (id);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);


--
-- Name: issued_certificates issued_certificates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issued_certificates
    ADD CONSTRAINT issued_certificates_pkey PRIMARY KEY (id);


--
-- Name: knowledge_base_versions knowledge_base_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base_versions
    ADD CONSTRAINT knowledge_base_versions_pkey PRIMARY KEY (id);


--
-- Name: knowledge_bases knowledge_bases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_bases
    ADD CONSTRAINT knowledge_bases_pkey PRIMARY KEY (id);


--
-- Name: locations locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.locations
    ADD CONSTRAINT locations_pkey PRIMARY KEY (id);


--
-- Name: mail_logs mail_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mail_logs
    ADD CONSTRAINT mail_logs_pkey PRIMARY KEY (id);


--
-- Name: messages_conversations messages_conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages_conversations
    ADD CONSTRAINT messages_conversations_pkey PRIMARY KEY (id);


--
-- Name: messages_media messages_media_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages_media
    ADD CONSTRAINT messages_media_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: messages_tags messages_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages_tags
    ADD CONSTRAINT messages_tags_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: organization_data organization_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_data
    ADD CONSTRAINT organization_data_pkey PRIMARY KEY (id);


--
-- Name: organization_eval_requests organization_eval_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_eval_requests
    ADD CONSTRAINT organization_eval_requests_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: prompt_generation_requests prompt_generation_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_generation_requests
    ADD CONSTRAINT prompt_generation_requests_pkey PRIMARY KEY (id);


--
-- Name: registrations registrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.registrations
    ADD CONSTRAINT registrations_pkey PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: saas saas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saas
    ADD CONSTRAINT saas_pkey PRIMARY KEY (id);


--
-- Name: saved_searches saved_searches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_searches
    ADD CONSTRAINT saved_searches_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: schema_seeds schema_seeds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_seeds
    ADD CONSTRAINT schema_seeds_pkey PRIMARY KEY (version, tenant);


--
-- Name: session_templates session_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_templates
    ADD CONSTRAINT session_templates_pkey PRIMARY KEY (id);


--
-- Name: sheets_data sheets_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sheets_data
    ADD CONSTRAINT sheets_data_pkey PRIMARY KEY (id);


--
-- Name: sheets sheets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sheets
    ADD CONSTRAINT sheets_pkey PRIMARY KEY (id);


--
-- Name: stats stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stats
    ADD CONSTRAINT stats_pkey PRIMARY KEY (id);


--
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: templates_tags templates_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.templates_tags
    ADD CONSTRAINT templates_tags_pkey PRIMARY KEY (id);


--
-- Name: tickets tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_pkey PRIMARY KEY (id);


--
-- Name: trackers trackers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trackers
    ADD CONSTRAINT trackers_pkey PRIMARY KEY (id);


--
-- Name: translate_logs translate_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.translate_logs
    ADD CONSTRAINT translate_logs_pkey PRIMARY KEY (id);


--
-- Name: trial_users trial_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trial_users
    ADD CONSTRAINT trial_users_pkey PRIMARY KEY (id);


--
-- Name: trigger_logs trigger_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger_logs
    ADD CONSTRAINT trigger_logs_pkey PRIMARY KEY (id);


--
-- Name: trigger_roles trigger_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger_roles
    ADD CONSTRAINT trigger_roles_pkey PRIMARY KEY (id);


--
-- Name: triggers triggers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.triggers
    ADD CONSTRAINT triggers_pkey PRIMARY KEY (id);


--
-- Name: user_jobs user_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_jobs
    ADD CONSTRAINT user_jobs_pkey PRIMARY KEY (id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (id);


--
-- Name: users_groups users_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_groups
    ADD CONSTRAINT users_groups_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users_tokens users_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_tokens
    ADD CONSTRAINT users_tokens_pkey PRIMARY KEY (id);


--
-- Name: versions versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT versions_pkey PRIMARY KEY (id);


--
-- Name: wa_groups_collections wa_groups_collections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups_collections
    ADD CONSTRAINT wa_groups_collections_pkey PRIMARY KEY (id);


--
-- Name: wa_groups_phones wa_groups_phones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups_phones
    ADD CONSTRAINT wa_groups_phones_pkey PRIMARY KEY (id);


--
-- Name: wa_groups wa_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups
    ADD CONSTRAINT wa_groups_pkey PRIMARY KEY (id);


--
-- Name: wa_managed_phones wa_managed_phones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_managed_phones
    ADD CONSTRAINT wa_managed_phones_pkey PRIMARY KEY (id);


--
-- Name: wa_messages wa_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_messages
    ADD CONSTRAINT wa_messages_pkey PRIMARY KEY (id);


--
-- Name: wa_polls wa_polls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_polls
    ADD CONSTRAINT wa_polls_pkey PRIMARY KEY (id);


--
-- Name: wa_reactions wa_reactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_reactions
    ADD CONSTRAINT wa_reactions_pkey PRIMARY KEY (id);


--
-- Name: webhook_logs webhook_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_logs
    ADD CONSTRAINT webhook_logs_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_form_revisions whatsapp_form_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_form_revisions
    ADD CONSTRAINT whatsapp_form_revisions_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_forms whatsapp_forms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_forms
    ADD CONSTRAINT whatsapp_forms_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_forms_responses whatsapp_forms_responses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_forms_responses
    ADD CONSTRAINT whatsapp_forms_responses_pkey PRIMARY KEY (id);


--
-- Name: fwf_flag_name_gate_target_idx; Type: INDEX; Schema: global; Owner: -
--

CREATE UNIQUE INDEX fwf_flag_name_gate_target_idx ON global.fun_with_flags_toggles USING btree (flag_name, gate_type, target);


--
-- Name: languages_label_locale_index; Type: INDEX; Schema: global; Owner: -
--

CREATE UNIQUE INDEX languages_label_locale_index ON global.languages USING btree (label, locale);


--
-- Name: oban_jobs_args_index; Type: INDEX; Schema: global; Owner: -
--

CREATE INDEX oban_jobs_args_index ON global.oban_jobs USING gin (args);


--
-- Name: oban_jobs_batch_index; Type: INDEX; Schema: global; Owner: -
--

CREATE INDEX oban_jobs_batch_index ON global.oban_jobs USING btree (state, ((meta ->> 'batch_id'::text)), ((meta ->> 'callback'::text))) WHERE (meta ? 'batch_id'::text);


--
-- Name: oban_jobs_chain_index; Type: INDEX; Schema: global; Owner: -
--

CREATE INDEX oban_jobs_chain_index ON global.oban_jobs USING btree (state, ((meta ->> 'chain_id'::text)), ((meta ->> 'on_hold'::text))) WHERE (meta ? 'chain_id'::text);


--
-- Name: oban_jobs_meta_index; Type: INDEX; Schema: global; Owner: -
--

CREATE INDEX oban_jobs_meta_index ON global.oban_jobs USING gin (meta);


--
-- Name: oban_jobs_partition_index; Type: INDEX; Schema: global; Owner: -
--

CREATE INDEX oban_jobs_partition_index ON global.oban_jobs USING btree (partition_key, queue, priority, scheduled_at, id) WHERE ((state = 'available'::global.oban_job_state) AND (partition_key IS NOT NULL));


--
-- Name: oban_jobs_state_cancelled_at_index; Type: INDEX; Schema: global; Owner: -
--

CREATE INDEX oban_jobs_state_cancelled_at_index ON global.oban_jobs USING btree (state, cancelled_at);


--
-- Name: oban_jobs_state_discarded_at_index; Type: INDEX; Schema: global; Owner: -
--

CREATE INDEX oban_jobs_state_discarded_at_index ON global.oban_jobs USING btree (state, discarded_at);


--
-- Name: oban_jobs_state_queue_priority_scheduled_at_id_index; Type: INDEX; Schema: global; Owner: -
--

CREATE INDEX oban_jobs_state_queue_priority_scheduled_at_id_index ON global.oban_jobs USING btree (state, queue, priority, scheduled_at, id);


--
-- Name: oban_jobs_sup_workflow_index; Type: INDEX; Schema: global; Owner: -
--

CREATE INDEX oban_jobs_sup_workflow_index ON global.oban_jobs USING btree (((meta ->> 'sup_workflow_id'::text)), state, ((meta ->> 'on_hold'::text))) WHERE (meta ? 'sup_workflow_id'::text);


--
-- Name: oban_jobs_unique_index; Type: INDEX; Schema: global; Owner: -
--

CREATE UNIQUE INDEX oban_jobs_unique_index ON global.oban_jobs USING btree (uniq_key) WHERE (uniq_key IS NOT NULL);


--
-- Name: oban_jobs_workflow_index; Type: INDEX; Schema: global; Owner: -
--

CREATE INDEX oban_jobs_workflow_index ON global.oban_jobs USING btree (((meta ->> 'workflow_id'::text)), state, ((meta ->> 'on_hold'::text)), ((meta ->> 'name'::text))) WHERE (meta ? 'workflow_id'::text);


--
-- Name: providers_name_index; Type: INDEX; Schema: global; Owner: -
--

CREATE UNIQUE INDEX providers_name_index ON global.providers USING btree (name);


--
-- Name: providers_shortcode_index; Type: INDEX; Schema: global; Owner: -
--

CREATE UNIQUE INDEX providers_shortcode_index ON global.providers USING btree (shortcode);


--
-- Name: ai_evaluations_assistant_config_version_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ai_evaluations_assistant_config_version_id_index ON public.ai_evaluations USING btree (assistant_config_version_id);


--
-- Name: ai_evaluations_golden_qa_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ai_evaluations_golden_qa_id_index ON public.ai_evaluations USING btree (golden_qa_id);


--
-- Name: ai_evaluations_name_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ai_evaluations_name_organization_id_index ON public.ai_evaluations USING btree (name, organization_id);


--
-- Name: ai_evaluations_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ai_evaluations_organization_id_index ON public.ai_evaluations USING btree (organization_id);


--
-- Name: ai_evaluations_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ai_evaluations_status_index ON public.ai_evaluations USING btree (status);


--
-- Name: ask_glific_conversations_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ask_glific_conversations_organization_id_index ON public.ask_glific_conversations USING btree (organization_id);


--
-- Name: ask_glific_conversations_user_id_conversation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ask_glific_conversations_user_id_conversation_id_index ON public.ask_glific_conversations USING btree (user_id, conversation_id);


--
-- Name: assistant_config_version_knowledge_base_versions_assistant_conf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assistant_config_version_knowledge_base_versions_assistant_conf ON public.assistant_config_version_knowledge_base_versions USING btree (assistant_config_version_id);


--
-- Name: assistant_config_version_knowledge_base_versions_knowledge_base; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assistant_config_version_knowledge_base_versions_knowledge_base ON public.assistant_config_version_knowledge_base_versions USING btree (knowledge_base_version_id);


--
-- Name: assistant_config_version_knowledge_base_versions_organization_i; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assistant_config_version_knowledge_base_versions_organization_i ON public.assistant_config_version_knowledge_base_versions USING btree (organization_id);


--
-- Name: assistant_config_versions_assistant_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assistant_config_versions_assistant_id_index ON public.assistant_config_versions USING btree (assistant_id);


--
-- Name: assistant_config_versions_assistant_id_version_number_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX assistant_config_versions_assistant_id_version_number_index ON public.assistant_config_versions USING btree (assistant_id, version_number);


--
-- Name: assistant_config_versions_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assistant_config_versions_organization_id_index ON public.assistant_config_versions USING btree (organization_id);


--
-- Name: assistants_active_config_version_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assistants_active_config_version_id_index ON public.assistants USING btree (active_config_version_id);


--
-- Name: assistants_assistant_display_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX assistants_assistant_display_id_organization_id_index ON public.assistants USING btree (assistant_display_id, organization_id);


--
-- Name: assistants_name_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX assistants_name_organization_id_index ON public.assistants USING btree (name, organization_id);


--
-- Name: assistants_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assistants_organization_id_index ON public.assistants USING btree (organization_id);


--
-- Name: bigquery_jobs_organization_id_table_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bigquery_jobs_organization_id_table_index ON public.bigquery_jobs USING btree (organization_id, "table");


--
-- Name: billings_organization_id_is_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX billings_organization_id_is_active_index ON public.billings USING btree (organization_id, is_active);


--
-- Name: billings_stripe_customer_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX billings_stripe_customer_id_index ON public.billings USING btree (stripe_customer_id);


--
-- Name: certificate_templates_label_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX certificate_templates_label_organization_id_index ON public.certificate_templates USING btree (label, organization_id);


--
-- Name: consulting_hours_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX consulting_hours_organization_id_index ON public.consulting_hours USING btree (organization_id);


--
-- Name: consulting_hours_when_staff_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX consulting_hours_when_staff_organization_id_index ON public.consulting_hours USING btree ("when", staff, organization_id);


--
-- Name: contact_histories_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_histories_contact_id_index ON public.contact_histories USING btree (contact_id);


--
-- Name: contact_histories_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_histories_organization_id_index ON public.contact_histories USING btree (organization_id);


--
-- Name: contact_histories_profile_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_histories_profile_id_index ON public.contact_histories USING btree (profile_id) WHERE (profile_id IS NOT NULL);


--
-- Name: contacts_active_profile_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_active_profile_id_index ON public.contacts USING btree (active_profile_id) WHERE (active_profile_id IS NOT NULL);


--
-- Name: contacts_bsp_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_bsp_status_index ON public.contacts USING btree (bsp_status);


--
-- Name: contacts_fields_name_organization_id_scope_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contacts_fields_name_organization_id_scope_index ON public.contacts_fields USING btree (name, organization_id, scope);


--
-- Name: contacts_fields_shortcode_organization_id_scope_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contacts_fields_shortcode_organization_id_scope_index ON public.contacts_fields USING btree (shortcode, organization_id, scope);


--
-- Name: contacts_groups_contact_id_group_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contacts_groups_contact_id_group_id_index ON public.contacts_groups USING btree (contact_id, group_id);


--
-- Name: contacts_groups_group_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_groups_group_id_organization_id_index ON public.contacts_groups USING btree (group_id, organization_id);


--
-- Name: contacts_last_communication_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_last_communication_at_index ON public.contacts USING btree (last_communication_at);


--
-- Name: contacts_last_message_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_last_message_at_index ON public.contacts USING btree (last_message_at) WHERE (last_message_at IS NOT NULL);


--
-- Name: contacts_name_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_name_organization_id_index ON public.contacts USING btree (name, organization_id);


--
-- Name: contacts_optin_status_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_optin_status_organization_id_index ON public.contacts USING btree (optin_status, organization_id);


--
-- Name: contacts_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_organization_id_index ON public.contacts USING btree (organization_id);


--
-- Name: contacts_phone_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contacts_phone_organization_id_index ON public.contacts USING btree (phone, organization_id);


--
-- Name: contacts_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_status_index ON public.contacts USING btree (status);


--
-- Name: contacts_tags_contact_id_tag_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contacts_tags_contact_id_tag_id_index ON public.contacts_tags USING btree (contact_id, tag_id);


--
-- Name: contacts_updated_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_updated_at_index ON public.contacts USING btree (updated_at);


--
-- Name: contacts_wa_groups_wa_group_id_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_wa_groups_wa_group_id_contact_id_index ON public.contacts_wa_groups USING btree (wa_group_id, contact_id);


--
-- Name: credentials_provider_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX credentials_provider_id_organization_id_index ON public.credentials USING btree (provider_id, organization_id);


--
-- Name: extensions_module_name_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX extensions_module_name_organization_id_index ON public.extensions USING btree (module, name, organization_id);


--
-- Name: extensions_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX extensions_organization_id_index ON public.extensions USING btree (organization_id);


--
-- Name: flow_broadcast_contacts_contact_id_flow_broadcast_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX flow_broadcast_contacts_contact_id_flow_broadcast_id_index ON public.message_broadcast_contacts USING btree (contact_id, message_broadcast_id);


--
-- Name: flow_contexts_completed_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_contexts_completed_at_index ON public.flow_contexts USING btree (completed_at) WHERE (completed_at IS NOT NULL);


--
-- Name: flow_contexts_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_contexts_contact_id_index ON public.flow_contexts USING btree (contact_id);


--
-- Name: flow_contexts_flow_broadcast_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_contexts_flow_broadcast_id_index ON public.flow_contexts USING btree (message_broadcast_id) WHERE (message_broadcast_id IS NOT NULL);


--
-- Name: flow_contexts_flow_id_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_contexts_flow_id_contact_id_index ON public.flow_contexts USING btree (flow_id, contact_id);


--
-- Name: flow_contexts_flow_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_contexts_flow_uuid_index ON public.flow_contexts USING btree (flow_uuid);


--
-- Name: flow_contexts_group_message_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_contexts_group_message_id_index ON public.flow_contexts USING btree (group_message_id) WHERE (group_message_id IS NOT NULL);


--
-- Name: flow_contexts_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_contexts_organization_id_index ON public.flow_contexts USING btree (organization_id);


--
-- Name: flow_contexts_parent_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_contexts_parent_id_index ON public.flow_contexts USING btree (parent_id) WHERE (parent_id IS NOT NULL);


--
-- Name: flow_contexts_updated_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_contexts_updated_at_index ON public.flow_contexts USING btree (updated_at);


--
-- Name: flow_contexts_wakeup_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_contexts_wakeup_at_index ON public.flow_contexts USING btree (wakeup_at) WHERE (wakeup_at IS NOT NULL);


--
-- Name: flow_counts_flow_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_counts_flow_id_index ON public.flow_counts USING btree (flow_id);


--
-- Name: flow_counts_organization_id_flow_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_counts_organization_id_flow_uuid_index ON public.flow_counts USING btree (organization_id, flow_uuid);


--
-- Name: flow_counts_uuid_flow_id_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX flow_counts_uuid_flow_id_type_index ON public.flow_counts USING btree (uuid, flow_id, type);


--
-- Name: flow_label_idx_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_label_idx_gin ON public.messages USING gin (flow_label public.gin_trgm_ops) WHERE (flow_label IS NOT NULL);


--
-- Name: flow_labels_name_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX flow_labels_name_organization_id_index ON public.flow_labels USING btree (name, organization_id);


--
-- Name: flow_results_contact_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_results_contact_id_organization_id_index ON public.flow_results USING btree (contact_id, organization_id);


--
-- Name: flow_results_flow_context_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX flow_results_flow_context_id_index ON public.flow_results USING btree (flow_context_id);


--
-- Name: flow_results_flow_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_results_flow_id_index ON public.flow_results USING btree (flow_id);


--
-- Name: flow_results_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_results_organization_id_index ON public.flow_results USING btree (organization_id);


--
-- Name: flow_results_updated_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_results_updated_at_index ON public.flow_results USING btree (updated_at);


--
-- Name: flow_revisions_flow_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_revisions_flow_id_index ON public.flow_revisions USING btree (flow_id);


--
-- Name: flow_revisions_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_revisions_organization_id_index ON public.flow_revisions USING btree (organization_id);


--
-- Name: flow_revisions_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flow_revisions_status_index ON public.flow_revisions USING btree (status);


--
-- Name: flow_roles_role_id_flow_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX flow_roles_role_id_flow_id_organization_id_index ON public.flow_roles USING btree (role_id, flow_id, organization_id);


--
-- Name: flows_is_pinned_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_is_pinned_organization_id_index ON public.flows USING btree (is_pinned, organization_id);


--
-- Name: flows_name_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX flows_name_organization_id_index ON public.flows USING btree (name, organization_id);


--
-- Name: flows_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flows_organization_id_index ON public.flows USING btree (organization_id);


--
-- Name: flows_uuid_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX flows_uuid_organization_id_index ON public.flows USING btree (uuid, organization_id);


--
-- Name: gcs_jobs_type_message_media_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX gcs_jobs_type_message_media_id_index ON public.gcs_jobs USING btree (type, message_media_id);


--
-- Name: gcs_jobs_type_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX gcs_jobs_type_organization_id_index ON public.gcs_jobs USING btree (type, organization_id);


--
-- Name: golden_qas_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX golden_qas_organization_id_index ON public.golden_qas USING btree (organization_id);


--
-- Name: golden_qas_organization_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX golden_qas_organization_id_inserted_at_index ON public.golden_qas USING btree (organization_id, inserted_at);


--
-- Name: golden_qas_organization_id_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX golden_qas_organization_id_name_index ON public.golden_qas USING btree (organization_id, name);


--
-- Name: group_roles_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX group_roles_organization_id_index ON public.group_roles USING btree (organization_id);


--
-- Name: group_roles_role_id_group_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX group_roles_role_id_group_id_organization_id_index ON public.group_roles USING btree (role_id, group_id, organization_id);


--
-- Name: groups_label_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX groups_label_organization_id_index ON public.groups USING btree (label, organization_id);


--
-- Name: groups_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX groups_organization_id_index ON public.groups USING btree (organization_id);


--
-- Name: interactive_templates_label_language_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX interactive_templates_label_language_id_organization_id_index ON public.interactive_templates USING btree (label, language_id, organization_id);


--
-- Name: interactive_templates_label_type_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX interactive_templates_label_type_organization_id_index ON public.interactive_templates USING btree (label, type, organization_id);


--
-- Name: interactive_templates_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX interactive_templates_organization_id_index ON public.interactive_templates USING btree (organization_id);


--
-- Name: invoices_customer_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoices_customer_id_index ON public.invoices USING btree (customer_id);


--
-- Name: invoices_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoices_organization_id_index ON public.invoices USING btree (organization_id);


--
-- Name: knowledge_base_versions_knowledge_base_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX knowledge_base_versions_knowledge_base_id_index ON public.knowledge_base_versions USING btree (knowledge_base_id);


--
-- Name: knowledge_base_versions_knowledge_base_id_version_number_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX knowledge_base_versions_knowledge_base_id_version_number_index ON public.knowledge_base_versions USING btree (knowledge_base_id, version_number);


--
-- Name: knowledge_base_versions_llm_service_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX knowledge_base_versions_llm_service_id_organization_id_index ON public.knowledge_base_versions USING btree (llm_service_id, organization_id);


--
-- Name: knowledge_base_versions_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX knowledge_base_versions_organization_id_index ON public.knowledge_base_versions USING btree (organization_id);


--
-- Name: knowledge_base_versions_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX knowledge_base_versions_status_index ON public.knowledge_base_versions USING btree (status);


--
-- Name: knowledge_bases_name_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX knowledge_bases_name_organization_id_index ON public.knowledge_bases USING btree (name, organization_id);


--
-- Name: knowledge_bases_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX knowledge_bases_organization_id_index ON public.knowledge_bases USING btree (organization_id);


--
-- Name: locations_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_contact_id_index ON public.locations USING btree (contact_id);


--
-- Name: locations_message_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_message_id_index ON public.locations USING btree (message_id);


--
-- Name: locations_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_organization_id_index ON public.locations USING btree (organization_id);


--
-- Name: locations_wa_message_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX locations_wa_message_id_index ON public.locations USING btree (wa_message_id);


--
-- Name: message_broadcast_contacts_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX message_broadcast_contacts_contact_id_index ON public.message_broadcast_contacts USING btree (contact_id);


--
-- Name: message_broadcast_contacts_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX message_broadcast_contacts_organization_id_index ON public.message_broadcast_contacts USING btree (organization_id);


--
-- Name: message_broadcast_contacts_updated_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX message_broadcast_contacts_updated_at_index ON public.message_broadcast_contacts USING btree (updated_at);


--
-- Name: message_broadcasts_completed_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX message_broadcasts_completed_at_index ON public.message_broadcasts USING btree (completed_at);


--
-- Name: message_broadcasts_flow_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX message_broadcasts_flow_id_index ON public.message_broadcasts USING btree (flow_id);


--
-- Name: message_broadcasts_group_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX message_broadcasts_group_id_index ON public.message_broadcasts USING btree (group_id);


--
-- Name: message_broadcasts_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX message_broadcasts_organization_id_index ON public.message_broadcasts USING btree (organization_id);


--
-- Name: message_broadcasts_updated_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX message_broadcasts_updated_at_index ON public.message_broadcasts USING btree (updated_at);


--
-- Name: messages_body_idx_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_body_idx_gin ON public.messages USING gin (body public.gin_trgm_ops) WHERE (body IS NOT NULL);


--
-- Name: messages_bsp_message_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX messages_bsp_message_id_organization_id_index ON public.messages USING btree (bsp_message_id, organization_id);


--
-- Name: messages_contact_id_channel_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_contact_id_channel_index ON public.messages USING btree (contact_id, channel);


--
-- Name: messages_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_contact_id_index ON public.messages USING btree (contact_id);


--
-- Name: messages_context_message_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_context_message_id_index ON public.messages USING btree (context_message_id) WHERE (context_message_id IS NOT NULL);


--
-- Name: messages_conversations_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_conversations_organization_id_index ON public.messages_conversations USING btree (organization_id);


--
-- Name: messages_flow_broadcast_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_flow_broadcast_id_index ON public.messages USING btree (message_broadcast_id) WHERE (message_broadcast_id IS NOT NULL);


--
-- Name: messages_flow_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_flow_id_index ON public.messages USING btree (flow_id);


--
-- Name: messages_group_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_group_id_index ON public.messages USING btree (group_id) WHERE (group_id IS NOT NULL);


--
-- Name: messages_group_message_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_group_message_id_index ON public.messages USING btree (group_message_id) WHERE (group_message_id IS NOT NULL);


--
-- Name: messages_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_inserted_at_index ON public.messages USING btree (inserted_at);


--
-- Name: messages_interactive_template_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_interactive_template_id_index ON public.messages USING btree (interactive_template_id) WHERE (interactive_template_id IS NOT NULL);


--
-- Name: messages_media_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_media_id_index ON public.messages USING btree (media_id) WHERE (media_id IS NOT NULL);


--
-- Name: messages_media_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_media_inserted_at_index ON public.messages_media USING btree (inserted_at);


--
-- Name: messages_media_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_media_organization_id_index ON public.messages_media USING btree (organization_id);


--
-- Name: messages_media_organization_id_url_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_media_organization_id_url_index ON public.messages_media USING btree (organization_id, url);


--
-- Name: INDEX messages_media_organization_id_url_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.messages_media_organization_id_url_index IS 'Backs media dedup lookup by org + url (glific#5319)';


--
-- Name: messages_media_updated_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_media_updated_at_index ON public.messages_media USING btree (updated_at);


--
-- Name: messages_message_number_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_message_number_index ON public.messages USING btree (message_number);


--
-- Name: messages_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_organization_id_index ON public.messages USING btree (organization_id);


--
-- Name: messages_profile_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_profile_id_index ON public.messages USING btree (profile_id) WHERE (profile_id IS NOT NULL);


--
-- Name: messages_receiver_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_receiver_id_index ON public.messages USING btree (receiver_id);


--
-- Name: messages_sender_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_sender_id_index ON public.messages USING btree (sender_id);


--
-- Name: messages_tags_message_id_tag_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX messages_tags_message_id_tag_id_index ON public.messages_tags USING btree (message_id, tag_id);


--
-- Name: messages_template_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_template_id_index ON public.messages USING btree (template_id) WHERE (template_id IS NOT NULL);


--
-- Name: messages_updated_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_updated_at_index ON public.messages USING btree (updated_at);


--
-- Name: messages_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_user_id_index ON public.messages USING btree (user_id) WHERE (user_id IS NOT NULL);


--
-- Name: messages_whatsapp_form_response_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_whatsapp_form_response_id_index ON public.messages USING btree (whatsapp_form_response_id);


--
-- Name: notifications_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_inserted_at_index ON public.notifications USING btree (inserted_at);


--
-- Name: notifications_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_organization_id_index ON public.notifications USING btree (organization_id);


--
-- Name: organization_eval_requests_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX organization_eval_requests_organization_id_index ON public.organization_eval_requests USING btree (organization_id);


--
-- Name: organizations_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX organizations_contact_id_index ON public.organizations USING btree (contact_id);


--
-- Name: organizations_deleted_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX organizations_deleted_index ON public.organizations USING btree (deleted_at) WHERE (deleted_at IS NULL);


--
-- Name: organizations_shortcode_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX organizations_shortcode_index ON public.organizations USING btree (shortcode);


--
-- Name: profiles_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX profiles_contact_id_index ON public.profiles USING btree (contact_id);


--
-- Name: profiles_language_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX profiles_language_id_index ON public.profiles USING btree (language_id);


--
-- Name: profiles_name_type_contact_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX profiles_name_type_contact_id_organization_id_index ON public.profiles USING btree (name, type, contact_id, organization_id);


--
-- Name: profiles_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX profiles_organization_id_index ON public.profiles USING btree (organization_id);


--
-- Name: prompt_generation_requests_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prompt_generation_requests_organization_id_index ON public.prompt_generation_requests USING btree (organization_id);


--
-- Name: prompt_generation_requests_request_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX prompt_generation_requests_request_id_organization_id_index ON public.prompt_generation_requests USING btree (request_id, organization_id);


--
-- Name: prompt_generation_requests_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prompt_generation_requests_user_id_index ON public.prompt_generation_requests USING btree (user_id);


--
-- Name: role_permissions_role_id_permission_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX role_permissions_role_id_permission_id_organization_id_index ON public.role_permissions USING btree (role_id, permission_id, organization_id);


--
-- Name: roles_label_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX roles_label_organization_id_index ON public.roles USING btree (label, organization_id);


--
-- Name: saved_searches_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX saved_searches_organization_id_index ON public.saved_searches USING btree (organization_id);


--
-- Name: saved_searches_shortcode_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX saved_searches_shortcode_organization_id_index ON public.saved_searches USING btree (shortcode, organization_id);


--
-- Name: session_templates_label_language_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX session_templates_label_language_id_organization_id_index ON public.session_templates USING btree (label, language_id, organization_id);


--
-- Name: session_templates_message_media_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX session_templates_message_media_id_index ON public.session_templates USING btree (message_media_id) WHERE (message_media_id IS NOT NULL);


--
-- Name: session_templates_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX session_templates_organization_id_index ON public.session_templates USING btree (organization_id);


--
-- Name: session_templates_shortcode_language_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX session_templates_shortcode_language_id_organization_id_index ON public.session_templates USING btree (shortcode, language_id, organization_id);


--
-- Name: session_templates_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX session_templates_uuid_index ON public.session_templates USING btree (uuid);


--
-- Name: sheets_data_key_sheet_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sheets_data_key_sheet_id_organization_id_index ON public.sheets_data USING btree (key, sheet_id, organization_id);


--
-- Name: sheets_data_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sheets_data_organization_id_index ON public.sheets_data USING btree (organization_id);


--
-- Name: sheets_data_sheet_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sheets_data_sheet_id_index ON public.sheets_data USING btree (sheet_id);


--
-- Name: sheets_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sheets_organization_id_index ON public.sheets USING btree (organization_id);


--
-- Name: sheets_url_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sheets_url_organization_id_index ON public.sheets USING btree (url, organization_id);


--
-- Name: stats_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stats_date_index ON public.stats USING btree (date);


--
-- Name: stats_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stats_organization_id_index ON public.stats USING btree (organization_id);


--
-- Name: tags_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tags_organization_id_index ON public.tags USING btree (organization_id);


--
-- Name: tags_shortcode_language_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tags_shortcode_language_id_organization_id_index ON public.tags USING btree (shortcode, language_id, organization_id);


--
-- Name: templates_tags_template_id_tag_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX templates_tags_template_id_tag_id_index ON public.templates_tags USING btree (template_id, tag_id);


--
-- Name: tickets_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tickets_organization_id_index ON public.tickets USING btree (organization_id);


--
-- Name: trackers_date_period_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX trackers_date_period_organization_id_index ON public.trackers USING btree (date, period, organization_id);


--
-- Name: trackers_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trackers_organization_id_index ON public.trackers USING btree (organization_id);


--
-- Name: trial_users_email_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX trial_users_email_index ON public.trial_users USING btree (email);


--
-- Name: trial_users_phone_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX trial_users_phone_index ON public.trial_users USING btree (phone);


--
-- Name: trigger_roles_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trigger_roles_organization_id_index ON public.trigger_roles USING btree (organization_id);


--
-- Name: trigger_roles_role_id_trigger_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX trigger_roles_role_id_trigger_id_organization_id_index ON public.trigger_roles USING btree (role_id, trigger_id, organization_id);


--
-- Name: triggers_flow_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX triggers_flow_id_index ON public.triggers USING btree (flow_id);


--
-- Name: triggers_last_trigger_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX triggers_last_trigger_at_index ON public.triggers USING btree (last_trigger_at);


--
-- Name: triggers_next_trigger_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX triggers_next_trigger_at_index ON public.triggers USING btree (next_trigger_at);


--
-- Name: triggers_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX triggers_organization_id_index ON public.triggers USING btree (organization_id);


--
-- Name: user_roles_user_id_role_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_roles_user_id_role_id_index ON public.user_roles USING btree (user_id, role_id);


--
-- Name: users_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_contact_id_index ON public.users USING btree (contact_id);


--
-- Name: users_groups_user_id_group_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_groups_user_id_group_id_index ON public.users_groups USING btree (user_id, group_id);


--
-- Name: users_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_organization_id_index ON public.users USING btree (organization_id);


--
-- Name: users_phone_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_phone_organization_id_index ON public.users USING btree (phone, organization_id);


--
-- Name: users_tokens_context_token_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_tokens_context_token_index ON public.users_tokens USING btree (context, token);


--
-- Name: users_tokens_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_tokens_user_id_index ON public.users_tokens USING btree (user_id);


--
-- Name: versions_entity_schema_entity_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX versions_entity_schema_entity_id_index ON public.versions USING btree (entity_schema, entity_id);


--
-- Name: versions_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX versions_organization_id_index ON public.versions USING btree (organization_id);


--
-- Name: versions_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX versions_user_id_index ON public.versions USING btree (user_id);


--
-- Name: INDEX versions_user_id_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.versions_user_id_index IS 'Speeds up FK nilify_all on user deletion (glific#5188)';


--
-- Name: wa_groups_bsp_id_wa_managed_phone_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX wa_groups_bsp_id_wa_managed_phone_id_organization_id_index ON public.wa_groups USING btree (bsp_id, wa_managed_phone_id, organization_id);


--
-- Name: wa_groups_collections_wa_group_id_group_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wa_groups_collections_wa_group_id_group_id_index ON public.wa_groups_collections USING btree (wa_group_id, group_id);


--
-- Name: wa_groups_collections_wa_group_id_group_id_organization_id_inde; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX wa_groups_collections_wa_group_id_group_id_organization_id_inde ON public.wa_groups_collections USING btree (wa_group_id, group_id, organization_id);


--
-- Name: wa_groups_phones_one_primary; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX wa_groups_phones_one_primary ON public.wa_groups_phones USING btree (wa_group_id) WHERE (is_primary IS TRUE);


--
-- Name: wa_groups_phones_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wa_groups_phones_organization_id_index ON public.wa_groups_phones USING btree (organization_id);


--
-- Name: wa_groups_phones_wa_group_id_wa_managed_phone_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX wa_groups_phones_wa_group_id_wa_managed_phone_id_index ON public.wa_groups_phones USING btree (wa_group_id, wa_managed_phone_id);


--
-- Name: wa_groups_wa_managed_phone_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wa_groups_wa_managed_phone_id_organization_id_index ON public.wa_groups USING btree (wa_managed_phone_id, organization_id);


--
-- Name: wa_managed_phones_phone_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX wa_managed_phones_phone_organization_id_index ON public.wa_managed_phones USING btree (phone, organization_id);


--
-- Name: wa_messages_bsp_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wa_messages_bsp_id_organization_id_index ON public.wa_messages USING btree (bsp_id, organization_id);


--
-- Name: wa_messages_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wa_messages_contact_id_index ON public.wa_messages USING btree (contact_id);


--
-- Name: wa_messages_media_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wa_messages_media_id_index ON public.wa_messages USING btree (media_id);


--
-- Name: wa_messages_poll_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wa_messages_poll_id_index ON public.wa_messages USING btree (poll_id) WHERE (poll_id IS NOT NULL);


--
-- Name: wa_messages_wa_managed_phone_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wa_messages_wa_managed_phone_id_index ON public.wa_messages USING btree (wa_managed_phone_id);


--
-- Name: wa_polls_label_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX wa_polls_label_organization_id_index ON public.wa_polls USING btree (label, organization_id);


--
-- Name: wa_polls_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX wa_polls_uuid_index ON public.wa_polls USING btree (uuid);


--
-- Name: wa_reactions_wa_message_id_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX wa_reactions_wa_message_id_contact_id_index ON public.wa_reactions USING btree (wa_message_id, contact_id);


--
-- Name: wa_reactions_wa_message_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wa_reactions_wa_message_id_index ON public.wa_reactions USING btree (wa_message_id);


--
-- Name: webhook_logs_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX webhook_logs_contact_id_index ON public.webhook_logs USING btree (contact_id) WHERE (contact_id IS NOT NULL);


--
-- Name: webhook_logs_flow_context_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX webhook_logs_flow_context_id_index ON public.webhook_logs USING btree (flow_context_id) WHERE (flow_context_id IS NOT NULL);


--
-- Name: webhook_logs_flow_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX webhook_logs_flow_id_index ON public.webhook_logs USING btree (flow_id);


--
-- Name: webhook_logs_wa_group_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX webhook_logs_wa_group_id_index ON public.webhook_logs USING btree (wa_group_id) WHERE (wa_group_id IS NOT NULL);


--
-- Name: whatsapp_form_revisions_whatsapp_form_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX whatsapp_form_revisions_whatsapp_form_id_index ON public.whatsapp_form_revisions USING btree (whatsapp_form_id);


--
-- Name: whatsapp_form_revisions_whatsapp_form_id_revision_number_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX whatsapp_form_revisions_whatsapp_form_id_revision_number_index ON public.whatsapp_form_revisions USING btree (whatsapp_form_id, revision_number);


--
-- Name: whatsapp_forms_name_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX whatsapp_forms_name_organization_id_index ON public.whatsapp_forms USING btree (name, organization_id);


--
-- Name: whatsapp_forms_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX whatsapp_forms_organization_id_index ON public.whatsapp_forms USING btree (organization_id);


--
-- Name: whatsapp_forms_responses_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX whatsapp_forms_responses_organization_id_index ON public.whatsapp_forms_responses USING btree (organization_id);


--
-- Name: whatsapp_forms_revision_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX whatsapp_forms_revision_id_index ON public.whatsapp_forms USING btree (revision_id);


--
-- Name: whatsapp_forms_sheet_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX whatsapp_forms_sheet_id_index ON public.whatsapp_forms USING btree (sheet_id);


--
-- Name: assistant_config_versions assistant_convfig_version_set_version_number; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER assistant_convfig_version_set_version_number BEFORE INSERT ON public.assistant_config_versions FOR EACH ROW WHEN ((new.version_number IS NULL)) EXECUTE FUNCTION public.set_assistant_config_version_number();


--
-- Name: tags delete_tag_ancestors_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER delete_tag_ancestors_trigger AFTER DELETE ON public.tags FOR EACH STATEMENT EXECUTE FUNCTION public.update_tag_ancestors();


--
-- Name: tags insert_tag_ancestors_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER insert_tag_ancestors_trigger AFTER INSERT ON public.tags FOR EACH STATEMENT EXECUTE FUNCTION public.update_tag_ancestors();


--
-- Name: knowledge_base_versions knowledge_base_version_set_version_number; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER knowledge_base_version_set_version_number BEFORE INSERT ON public.knowledge_base_versions FOR EACH ROW WHEN ((new.version_number IS NULL)) EXECUTE FUNCTION public.set_knowledge_base_version_number();


--
-- Name: messages message_after_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER message_after_insert_trigger AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION public.message_after_insert_callback();


--
-- Name: messages message_before_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER message_before_insert_trigger BEFORE INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION public.message_before_insert_callback();


--
-- Name: contact_histories remove_old_history_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER remove_old_history_trigger AFTER INSERT ON public.contact_histories FOR EACH ROW EXECUTE FUNCTION public.remove_old_history();


--
-- Name: whatsapp_form_revisions set_whatsapp_form_revision_number_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_whatsapp_form_revision_number_trigger BEFORE INSERT ON public.whatsapp_form_revisions FOR EACH ROW EXECUTE FUNCTION public.set_whatsapp_form_revision_number();


--
-- Name: contacts_tags update_contact_updated_at_on_tagging_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_contact_updated_at_on_tagging_trigger AFTER INSERT OR DELETE OR UPDATE ON public.contacts_tags FOR EACH ROW EXECUTE FUNCTION public.update_contact_updated_at_on_tagging();


--
-- Name: contacts_groups update_contact_updated_at_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_contact_updated_at_trigger AFTER INSERT OR DELETE OR UPDATE ON public.contacts_groups FOR EACH ROW EXECUTE FUNCTION public.update_contact_updated_at();


--
-- Name: flow_revisions update_flow_revision_number_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_flow_revision_number_trigger AFTER INSERT ON public.flow_revisions FOR EACH ROW EXECUTE FUNCTION public.update_flow_revision_number();


--
-- Name: messages_tags update_message_updated_at_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_message_updated_at_trigger AFTER INSERT OR DELETE OR UPDATE ON public.messages_tags FOR EACH ROW EXECUTE FUNCTION public.update_message_updated_at();


--
-- Name: organizations update_organization_id_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_organization_id_trigger AFTER INSERT ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.update_organization_id();


--
-- Name: contact_histories update_profile_id_on_new_contact_history; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_profile_id_on_new_contact_history AFTER INSERT ON public.contact_histories FOR EACH ROW EXECUTE FUNCTION public.update_profile_id_on_new_contact_history();


--
-- Name: flow_contexts update_profile_id_on_new_flow_context; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_profile_id_on_new_flow_context AFTER INSERT ON public.flow_contexts FOR EACH ROW EXECUTE FUNCTION public.update_profile_id_on_new_flow_context();


--
-- Name: flow_results update_profile_id_on_new_flow_result; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_profile_id_on_new_flow_result AFTER INSERT ON public.flow_results FOR EACH ROW EXECUTE FUNCTION public.update_profile_id_on_new_flow_result();


--
-- Name: tags update_tag_ancestors_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_tag_ancestors_trigger AFTER UPDATE OF parent_id ON public.tags FOR EACH STATEMENT EXECUTE FUNCTION public.update_tag_ancestors();


--
-- Name: wa_messages wa_message_after_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER wa_message_after_insert_trigger AFTER INSERT ON public.wa_messages FOR EACH ROW EXECUTE FUNCTION public.wa_message_after_insert_callback();


--
-- Name: wa_messages wa_message_before_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER wa_message_before_insert_trigger BEFORE INSERT ON public.wa_messages FOR EACH ROW EXECUTE FUNCTION public.wa_message_before_insert_callback();


--
-- Name: ai_evaluations ai_evaluations_assistant_config_version_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_evaluations
    ADD CONSTRAINT ai_evaluations_assistant_config_version_id_fkey FOREIGN KEY (assistant_config_version_id) REFERENCES public.assistant_config_versions(id) ON DELETE CASCADE;


--
-- Name: ai_evaluations ai_evaluations_golden_qa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_evaluations
    ADD CONSTRAINT ai_evaluations_golden_qa_id_fkey FOREIGN KEY (golden_qa_id) REFERENCES public.golden_qas(id) ON DELETE RESTRICT;


--
-- Name: ai_evaluations ai_evaluations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_evaluations
    ADD CONSTRAINT ai_evaluations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: ask_glific_conversations ask_glific_conversations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ask_glific_conversations
    ADD CONSTRAINT ask_glific_conversations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: ask_glific_conversations ask_glific_conversations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ask_glific_conversations
    ADD CONSTRAINT ask_glific_conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: assistant_config_version_knowledge_base_versions assistant_config_version_knowledge_base_versions_assistant_conf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_config_version_knowledge_base_versions
    ADD CONSTRAINT assistant_config_version_knowledge_base_versions_assistant_conf FOREIGN KEY (assistant_config_version_id) REFERENCES public.assistant_config_versions(id) ON DELETE CASCADE;


--
-- Name: assistant_config_version_knowledge_base_versions assistant_config_version_knowledge_base_versions_knowledge_base; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_config_version_knowledge_base_versions
    ADD CONSTRAINT assistant_config_version_knowledge_base_versions_knowledge_base FOREIGN KEY (knowledge_base_version_id) REFERENCES public.knowledge_base_versions(id) ON DELETE CASCADE;


--
-- Name: assistant_config_version_knowledge_base_versions assistant_config_version_knowledge_base_versions_organization_i; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_config_version_knowledge_base_versions
    ADD CONSTRAINT assistant_config_version_knowledge_base_versions_organization_i FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: assistant_config_versions assistant_config_versions_assistant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_config_versions
    ADD CONSTRAINT assistant_config_versions_assistant_id_fkey FOREIGN KEY (assistant_id) REFERENCES public.assistants(id) ON DELETE CASCADE;


--
-- Name: assistant_config_versions assistant_config_versions_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_config_versions
    ADD CONSTRAINT assistant_config_versions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: assistants assistants_active_config_version_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistants
    ADD CONSTRAINT assistants_active_config_version_id_fkey FOREIGN KEY (active_config_version_id) REFERENCES public.assistant_config_versions(id);


--
-- Name: assistants assistants_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistants
    ADD CONSTRAINT assistants_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: bigquery_jobs bigquery_jobs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bigquery_jobs
    ADD CONSTRAINT bigquery_jobs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: billings billings_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billings
    ADD CONSTRAINT billings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: certificate_templates certificate_templates_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificate_templates
    ADD CONSTRAINT certificate_templates_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: consulting_hours consulting_hours_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consulting_hours
    ADD CONSTRAINT consulting_hours_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: contact_histories contact_histories_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_histories
    ADD CONSTRAINT contact_histories_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: contact_histories contact_histories_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_histories
    ADD CONSTRAINT contact_histories_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: contact_histories contact_histories_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_histories
    ADD CONSTRAINT contact_histories_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: contacts contacts_active_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_active_profile_id_fkey FOREIGN KEY (active_profile_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: contacts_fields contacts_fields_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_fields
    ADD CONSTRAINT contacts_fields_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: contacts_groups contacts_groups_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_groups
    ADD CONSTRAINT contacts_groups_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: contacts_groups contacts_groups_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_groups
    ADD CONSTRAINT contacts_groups_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: contacts_groups contacts_groups_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_groups
    ADD CONSTRAINT contacts_groups_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: contacts contacts_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_language_id_fkey FOREIGN KEY (language_id) REFERENCES global.languages(id) ON DELETE RESTRICT;


--
-- Name: contacts contacts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: contacts_tags contacts_tags_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_tags
    ADD CONSTRAINT contacts_tags_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: contacts_tags contacts_tags_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_tags
    ADD CONSTRAINT contacts_tags_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: contacts_tags contacts_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_tags
    ADD CONSTRAINT contacts_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id) ON DELETE CASCADE;


--
-- Name: contacts_wa_groups contacts_wa_groups_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_wa_groups
    ADD CONSTRAINT contacts_wa_groups_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: contacts_wa_groups contacts_wa_groups_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_wa_groups
    ADD CONSTRAINT contacts_wa_groups_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: contacts_wa_groups contacts_wa_groups_wa_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_wa_groups
    ADD CONSTRAINT contacts_wa_groups_wa_group_id_fkey FOREIGN KEY (wa_group_id) REFERENCES public.wa_groups(id) ON DELETE CASCADE;


--
-- Name: credentials credentials_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: credentials credentials_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES global.providers(id);


--
-- Name: extensions extensions_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extensions
    ADD CONSTRAINT extensions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: message_broadcast_contacts flow_broadcast_contacts_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_broadcast_contacts
    ADD CONSTRAINT flow_broadcast_contacts_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: message_broadcast_contacts flow_broadcast_contacts_flow_broadcast_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_broadcast_contacts
    ADD CONSTRAINT flow_broadcast_contacts_flow_broadcast_id_fkey FOREIGN KEY (message_broadcast_id) REFERENCES public.message_broadcasts(id) ON DELETE CASCADE;


--
-- Name: message_broadcast_contacts flow_broadcast_contacts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_broadcast_contacts
    ADD CONSTRAINT flow_broadcast_contacts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: message_broadcasts flow_broadcasts_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_broadcasts
    ADD CONSTRAINT flow_broadcasts_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows(id) ON DELETE CASCADE;


--
-- Name: message_broadcasts flow_broadcasts_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_broadcasts
    ADD CONSTRAINT flow_broadcasts_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: message_broadcasts flow_broadcasts_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_broadcasts
    ADD CONSTRAINT flow_broadcasts_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE SET NULL;


--
-- Name: message_broadcasts flow_broadcasts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_broadcasts
    ADD CONSTRAINT flow_broadcasts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: message_broadcasts flow_broadcasts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_broadcasts
    ADD CONSTRAINT flow_broadcasts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: flow_contexts flow_contexts_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_contexts
    ADD CONSTRAINT flow_contexts_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: flow_contexts flow_contexts_flow_broadcast_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_contexts
    ADD CONSTRAINT flow_contexts_flow_broadcast_id_fkey FOREIGN KEY (message_broadcast_id) REFERENCES public.message_broadcasts(id) ON DELETE SET NULL;


--
-- Name: flow_contexts flow_contexts_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_contexts
    ADD CONSTRAINT flow_contexts_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows(id) ON DELETE CASCADE;


--
-- Name: flow_contexts flow_contexts_group_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_contexts
    ADD CONSTRAINT flow_contexts_group_message_id_fkey FOREIGN KEY (group_message_id) REFERENCES public.messages(id) ON DELETE SET NULL;


--
-- Name: flow_contexts flow_contexts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_contexts
    ADD CONSTRAINT flow_contexts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: flow_contexts flow_contexts_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_contexts
    ADD CONSTRAINT flow_contexts_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.flow_contexts(id) ON DELETE SET NULL;


--
-- Name: flow_contexts flow_contexts_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_contexts
    ADD CONSTRAINT flow_contexts_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: flow_contexts flow_contexts_wa_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_contexts
    ADD CONSTRAINT flow_contexts_wa_group_id_fkey FOREIGN KEY (wa_group_id) REFERENCES public.wa_groups(id) ON DELETE CASCADE;


--
-- Name: flow_counts flow_counts_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_counts
    ADD CONSTRAINT flow_counts_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows(id) ON DELETE CASCADE;


--
-- Name: flow_counts flow_counts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_counts
    ADD CONSTRAINT flow_counts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: flow_labels flow_labels_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_labels
    ADD CONSTRAINT flow_labels_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: flow_results flow_results_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_results
    ADD CONSTRAINT flow_results_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: flow_results flow_results_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_results
    ADD CONSTRAINT flow_results_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows(id) ON DELETE CASCADE;


--
-- Name: flow_results flow_results_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_results
    ADD CONSTRAINT flow_results_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: flow_results flow_results_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_results
    ADD CONSTRAINT flow_results_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: flow_revisions flow_revisions_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_revisions
    ADD CONSTRAINT flow_revisions_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows(id) ON DELETE CASCADE;


--
-- Name: flow_revisions flow_revisions_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_revisions
    ADD CONSTRAINT flow_revisions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: flow_revisions flow_revisions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_revisions
    ADD CONSTRAINT flow_revisions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: flow_roles flow_roles_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_roles
    ADD CONSTRAINT flow_roles_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows(id) ON DELETE CASCADE;


--
-- Name: flow_roles flow_roles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_roles
    ADD CONSTRAINT flow_roles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: flow_roles flow_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flow_roles
    ADD CONSTRAINT flow_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: flows flows_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flows
    ADD CONSTRAINT flows_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: flows flows_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flows
    ADD CONSTRAINT flows_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id);


--
-- Name: gcs_jobs gcs_jobs_message_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gcs_jobs
    ADD CONSTRAINT gcs_jobs_message_media_id_fkey FOREIGN KEY (message_media_id) REFERENCES public.messages_media(id) ON DELETE SET NULL;


--
-- Name: gcs_jobs gcs_jobs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gcs_jobs
    ADD CONSTRAINT gcs_jobs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: golden_qas golden_qas_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_qas
    ADD CONSTRAINT golden_qas_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: group_roles group_roles_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_roles
    ADD CONSTRAINT group_roles_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: group_roles group_roles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_roles
    ADD CONSTRAINT group_roles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: group_roles group_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_roles
    ADD CONSTRAINT group_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: groups groups_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: intents intents_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intents
    ADD CONSTRAINT intents_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: interactive_templates interactive_templates_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.interactive_templates
    ADD CONSTRAINT interactive_templates_language_id_fkey FOREIGN KEY (language_id) REFERENCES global.languages(id) ON DELETE RESTRICT;


--
-- Name: interactive_templates interactive_templates_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.interactive_templates
    ADD CONSTRAINT interactive_templates_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: interactive_templates interactive_templates_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.interactive_templates
    ADD CONSTRAINT interactive_templates_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id);


--
-- Name: invoices invoices_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: issued_certificates issued_certificates_certificate_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issued_certificates
    ADD CONSTRAINT issued_certificates_certificate_template_id_fkey FOREIGN KEY (certificate_template_id) REFERENCES public.certificate_templates(id) ON DELETE CASCADE;


--
-- Name: issued_certificates issued_certificates_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issued_certificates
    ADD CONSTRAINT issued_certificates_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: issued_certificates issued_certificates_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issued_certificates
    ADD CONSTRAINT issued_certificates_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: knowledge_base_versions knowledge_base_versions_knowledge_base_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base_versions
    ADD CONSTRAINT knowledge_base_versions_knowledge_base_id_fkey FOREIGN KEY (knowledge_base_id) REFERENCES public.knowledge_bases(id) ON DELETE CASCADE;


--
-- Name: knowledge_base_versions knowledge_base_versions_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base_versions
    ADD CONSTRAINT knowledge_base_versions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: knowledge_bases knowledge_bases_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_bases
    ADD CONSTRAINT knowledge_bases_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: locations locations_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.locations
    ADD CONSTRAINT locations_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: locations locations_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.locations
    ADD CONSTRAINT locations_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE CASCADE;


--
-- Name: locations locations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.locations
    ADD CONSTRAINT locations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: locations locations_wa_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.locations
    ADD CONSTRAINT locations_wa_message_id_fkey FOREIGN KEY (wa_message_id) REFERENCES public.wa_messages(id) ON DELETE CASCADE;


--
-- Name: mail_logs mail_logs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mail_logs
    ADD CONSTRAINT mail_logs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: message_broadcasts message_broadcasts_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_broadcasts
    ADD CONSTRAINT message_broadcasts_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows(id) ON DELETE CASCADE;


--
-- Name: messages messages_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: messages messages_context_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_context_message_id_fkey FOREIGN KEY (context_message_id) REFERENCES public.messages(id) ON DELETE CASCADE;


--
-- Name: messages_conversations messages_conversations_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages_conversations
    ADD CONSTRAINT messages_conversations_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE CASCADE;


--
-- Name: messages_conversations messages_conversations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages_conversations
    ADD CONSTRAINT messages_conversations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: messages messages_flow_broadcast_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_flow_broadcast_id_fkey FOREIGN KEY (message_broadcast_id) REFERENCES public.message_broadcasts(id) ON DELETE SET NULL;


--
-- Name: messages messages_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows(id) ON DELETE SET NULL;


--
-- Name: messages messages_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: messages messages_group_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_group_message_id_fkey FOREIGN KEY (group_message_id) REFERENCES public.messages(id) ON DELETE SET NULL;


--
-- Name: messages messages_interactive_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_interactive_template_id_fkey FOREIGN KEY (interactive_template_id) REFERENCES public.interactive_templates(id) ON DELETE SET NULL;


--
-- Name: messages messages_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.messages_media(id) ON DELETE SET NULL;


--
-- Name: messages_media messages_media_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages_media
    ADD CONSTRAINT messages_media_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: messages messages_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: messages messages_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: messages messages_receiver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_receiver_id_fkey FOREIGN KEY (receiver_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: messages messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: messages_tags messages_tags_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages_tags
    ADD CONSTRAINT messages_tags_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE CASCADE;


--
-- Name: messages_tags messages_tags_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages_tags
    ADD CONSTRAINT messages_tags_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: messages_tags messages_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages_tags
    ADD CONSTRAINT messages_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id) ON DELETE CASCADE;


--
-- Name: messages messages_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.session_templates(id) ON DELETE SET NULL;


--
-- Name: messages messages_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: messages messages_whatsapp_form_response_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_whatsapp_form_response_id_fkey FOREIGN KEY (whatsapp_form_response_id) REFERENCES public.whatsapp_forms_responses(id) ON DELETE SET NULL;


--
-- Name: notifications notifications_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: organization_data organization_data_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_data
    ADD CONSTRAINT organization_data_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: organization_eval_requests organization_eval_requests_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_eval_requests
    ADD CONSTRAINT organization_eval_requests_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: organizations organizations_default_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_default_language_id_fkey FOREIGN KEY (default_language_id) REFERENCES global.languages(id) ON DELETE RESTRICT;


--
-- Name: organizations organizations_newcontact_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_newcontact_flow_id_fkey FOREIGN KEY (newcontact_flow_id) REFERENCES public.flows(id) ON DELETE SET NULL;


--
-- Name: organizations organizations_optin_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_optin_flow_id_fkey FOREIGN KEY (optin_flow_id) REFERENCES public.flows(id) ON DELETE SET NULL;


--
-- Name: organizations organizations_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_provider_id_fkey FOREIGN KEY (bsp_id) REFERENCES global.providers(id);


--
-- Name: profiles profiles_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_language_id_fkey FOREIGN KEY (language_id) REFERENCES global.languages(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: prompt_generation_requests prompt_generation_requests_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_generation_requests
    ADD CONSTRAINT prompt_generation_requests_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: prompt_generation_requests prompt_generation_requests_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_generation_requests
    ADD CONSTRAINT prompt_generation_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: registrations registrations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.registrations
    ADD CONSTRAINT registrations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES global.permissions(id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: roles roles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: saas saas_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saas
    ADD CONSTRAINT saas_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: saved_searches saved_searches_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_searches
    ADD CONSTRAINT saved_searches_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: session_templates session_templates_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_templates
    ADD CONSTRAINT session_templates_language_id_fkey FOREIGN KEY (language_id) REFERENCES global.languages(id) ON DELETE RESTRICT;


--
-- Name: session_templates session_templates_message_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_templates
    ADD CONSTRAINT session_templates_message_media_id_fkey FOREIGN KEY (message_media_id) REFERENCES public.messages_media(id) ON DELETE CASCADE;


--
-- Name: session_templates session_templates_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_templates
    ADD CONSTRAINT session_templates_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: session_templates session_templates_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_templates
    ADD CONSTRAINT session_templates_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.session_templates(id) ON DELETE SET NULL;


--
-- Name: session_templates session_templates_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_templates
    ADD CONSTRAINT session_templates_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id);


--
-- Name: sheets_data sheets_data_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sheets_data
    ADD CONSTRAINT sheets_data_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: sheets_data sheets_data_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sheets_data
    ADD CONSTRAINT sheets_data_sheet_id_fkey FOREIGN KEY (sheet_id) REFERENCES public.sheets(id) ON DELETE CASCADE;


--
-- Name: sheets sheets_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sheets
    ADD CONSTRAINT sheets_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: stats stats_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stats
    ADD CONSTRAINT stats_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: tags tags_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_language_id_fkey FOREIGN KEY (language_id) REFERENCES global.languages(id) ON DELETE RESTRICT;


--
-- Name: tags tags_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: tags tags_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.tags(id) ON DELETE SET NULL;


--
-- Name: templates_tags templates_tags_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.templates_tags
    ADD CONSTRAINT templates_tags_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: templates_tags templates_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.templates_tags
    ADD CONSTRAINT templates_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id) ON DELETE CASCADE;


--
-- Name: templates_tags templates_tags_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.templates_tags
    ADD CONSTRAINT templates_tags_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.session_templates(id) ON DELETE CASCADE;


--
-- Name: tickets tickets_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: tickets tickets_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows(id) ON DELETE CASCADE;


--
-- Name: tickets tickets_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: tickets tickets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: trackers trackers_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trackers
    ADD CONSTRAINT trackers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: translate_logs translate_logs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.translate_logs
    ADD CONSTRAINT translate_logs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: trigger_logs trigger_logs_flow_context_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger_logs
    ADD CONSTRAINT trigger_logs_flow_context_id_fkey FOREIGN KEY (flow_context_id) REFERENCES public.flow_contexts(id) ON DELETE CASCADE;


--
-- Name: trigger_logs trigger_logs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger_logs
    ADD CONSTRAINT trigger_logs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: trigger_logs trigger_logs_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger_logs
    ADD CONSTRAINT trigger_logs_trigger_id_fkey FOREIGN KEY (trigger_id) REFERENCES public.triggers(id) ON DELETE CASCADE;


--
-- Name: trigger_roles trigger_roles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger_roles
    ADD CONSTRAINT trigger_roles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: trigger_roles trigger_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger_roles
    ADD CONSTRAINT trigger_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: trigger_roles trigger_roles_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger_roles
    ADD CONSTRAINT trigger_roles_trigger_id_fkey FOREIGN KEY (trigger_id) REFERENCES public.triggers(id) ON DELETE CASCADE;


--
-- Name: triggers triggers_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.triggers
    ADD CONSTRAINT triggers_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows(id) ON DELETE CASCADE;


--
-- Name: triggers triggers_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.triggers
    ADD CONSTRAINT triggers_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: triggers triggers_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.triggers
    ADD CONSTRAINT triggers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: user_jobs user_jobs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_jobs
    ADD CONSTRAINT user_jobs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: users users_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: users_groups users_groups_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_groups
    ADD CONSTRAINT users_groups_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: users_groups users_groups_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_groups
    ADD CONSTRAINT users_groups_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: users_groups users_groups_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_groups
    ADD CONSTRAINT users_groups_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: users users_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_language_id_fkey FOREIGN KEY (language_id) REFERENCES global.languages(id) ON DELETE RESTRICT;


--
-- Name: users users_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: users_tokens users_tokens_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_tokens
    ADD CONSTRAINT users_tokens_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: users_tokens users_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users_tokens
    ADD CONSTRAINT users_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: versions versions_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT versions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: versions versions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT versions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: wa_groups_collections wa_groups_collections_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups_collections
    ADD CONSTRAINT wa_groups_collections_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: wa_groups_collections wa_groups_collections_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups_collections
    ADD CONSTRAINT wa_groups_collections_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wa_groups_collections wa_groups_collections_wa_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups_collections
    ADD CONSTRAINT wa_groups_collections_wa_group_id_fkey FOREIGN KEY (wa_group_id) REFERENCES public.wa_groups(id) ON DELETE CASCADE;


--
-- Name: wa_groups wa_groups_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups
    ADD CONSTRAINT wa_groups_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wa_groups_phones wa_groups_phones_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups_phones
    ADD CONSTRAINT wa_groups_phones_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wa_groups_phones wa_groups_phones_wa_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups_phones
    ADD CONSTRAINT wa_groups_phones_wa_group_id_fkey FOREIGN KEY (wa_group_id) REFERENCES public.wa_groups(id) ON DELETE CASCADE;


--
-- Name: wa_groups_phones wa_groups_phones_wa_managed_phone_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups_phones
    ADD CONSTRAINT wa_groups_phones_wa_managed_phone_id_fkey FOREIGN KEY (wa_managed_phone_id) REFERENCES public.wa_managed_phones(id) ON DELETE CASCADE;


--
-- Name: wa_groups wa_groups_wa_managed_phone_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_groups
    ADD CONSTRAINT wa_groups_wa_managed_phone_id_fkey FOREIGN KEY (wa_managed_phone_id) REFERENCES public.wa_managed_phones(id) ON DELETE CASCADE;


--
-- Name: wa_managed_phones wa_managed_phones_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_managed_phones
    ADD CONSTRAINT wa_managed_phones_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: wa_managed_phones wa_managed_phones_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_managed_phones
    ADD CONSTRAINT wa_managed_phones_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wa_messages wa_messages_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_messages
    ADD CONSTRAINT wa_messages_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: wa_messages wa_messages_context_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_messages
    ADD CONSTRAINT wa_messages_context_message_id_fkey FOREIGN KEY (context_message_id) REFERENCES public.wa_messages(id) ON DELETE CASCADE;


--
-- Name: wa_messages wa_messages_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_messages
    ADD CONSTRAINT wa_messages_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: wa_messages wa_messages_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_messages
    ADD CONSTRAINT wa_messages_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.messages_media(id) ON DELETE CASCADE;


--
-- Name: wa_messages wa_messages_message_broadcast_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_messages
    ADD CONSTRAINT wa_messages_message_broadcast_id_fkey FOREIGN KEY (message_broadcast_id) REFERENCES public.message_broadcasts(id) ON DELETE CASCADE;


--
-- Name: wa_messages wa_messages_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_messages
    ADD CONSTRAINT wa_messages_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wa_messages wa_messages_poll_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_messages
    ADD CONSTRAINT wa_messages_poll_id_fkey FOREIGN KEY (poll_id) REFERENCES public.wa_polls(id) ON DELETE SET NULL;


--
-- Name: wa_messages wa_messages_wa_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_messages
    ADD CONSTRAINT wa_messages_wa_group_id_fkey FOREIGN KEY (wa_group_id) REFERENCES public.wa_groups(id) ON DELETE CASCADE;


--
-- Name: wa_messages wa_messages_wa_managed_phone_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_messages
    ADD CONSTRAINT wa_messages_wa_managed_phone_id_fkey FOREIGN KEY (wa_managed_phone_id) REFERENCES public.wa_managed_phones(id) ON DELETE CASCADE;


--
-- Name: wa_polls wa_polls_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_polls
    ADD CONSTRAINT wa_polls_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wa_reactions wa_reactions_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_reactions
    ADD CONSTRAINT wa_reactions_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: wa_reactions wa_reactions_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_reactions
    ADD CONSTRAINT wa_reactions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: wa_reactions wa_reactions_wa_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wa_reactions
    ADD CONSTRAINT wa_reactions_wa_message_id_fkey FOREIGN KEY (wa_message_id) REFERENCES public.wa_messages(id) ON DELETE CASCADE;


--
-- Name: webhook_logs webhook_logs_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_logs
    ADD CONSTRAINT webhook_logs_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: webhook_logs webhook_logs_flow_context_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_logs
    ADD CONSTRAINT webhook_logs_flow_context_id_fkey FOREIGN KEY (flow_context_id) REFERENCES public.flow_contexts(id) ON DELETE CASCADE;


--
-- Name: webhook_logs webhook_logs_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_logs
    ADD CONSTRAINT webhook_logs_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows(id) ON DELETE CASCADE;


--
-- Name: webhook_logs webhook_logs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_logs
    ADD CONSTRAINT webhook_logs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: webhook_logs webhook_logs_wa_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_logs
    ADD CONSTRAINT webhook_logs_wa_group_id_fkey FOREIGN KEY (wa_group_id) REFERENCES public.wa_groups(id) ON DELETE CASCADE;


--
-- Name: whatsapp_form_revisions whatsapp_form_revisions_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_form_revisions
    ADD CONSTRAINT whatsapp_form_revisions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: whatsapp_form_revisions whatsapp_form_revisions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_form_revisions
    ADD CONSTRAINT whatsapp_form_revisions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: whatsapp_form_revisions whatsapp_form_revisions_whatsapp_form_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_form_revisions
    ADD CONSTRAINT whatsapp_form_revisions_whatsapp_form_id_fkey FOREIGN KEY (whatsapp_form_id) REFERENCES public.whatsapp_forms(id) ON DELETE CASCADE;


--
-- Name: whatsapp_forms whatsapp_forms_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_forms
    ADD CONSTRAINT whatsapp_forms_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: whatsapp_forms_responses whatsapp_forms_responses_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_forms_responses
    ADD CONSTRAINT whatsapp_forms_responses_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: whatsapp_forms_responses whatsapp_forms_responses_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_forms_responses
    ADD CONSTRAINT whatsapp_forms_responses_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: whatsapp_forms_responses whatsapp_forms_responses_whatsapp_form_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_forms_responses
    ADD CONSTRAINT whatsapp_forms_responses_whatsapp_form_id_fkey FOREIGN KEY (whatsapp_form_id) REFERENCES public.whatsapp_forms(id) ON DELETE CASCADE;


--
-- Name: whatsapp_forms whatsapp_forms_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_forms
    ADD CONSTRAINT whatsapp_forms_revision_id_fkey FOREIGN KEY (revision_id) REFERENCES public.whatsapp_form_revisions(id) ON DELETE RESTRICT;


--
-- Name: whatsapp_forms whatsapp_forms_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_forms
    ADD CONSTRAINT whatsapp_forms_sheet_id_fkey FOREIGN KEY (sheet_id) REFERENCES public.sheets(id) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--

\unrestrict H2xfx7ERE4SrIeMiG3eYz7cFVhmyRKWtNmIzcMpTKJGeXmb5eiMQgq1gUC0CEim

INSERT INTO public."schema_migrations" (version) VALUES (20200101010533);
INSERT INTO public."schema_migrations" (version) VALUES (20200601193405);
INSERT INTO public."schema_migrations" (version) VALUES (20200615073630);
INSERT INTO public."schema_migrations" (version) VALUES (20200710170410);
INSERT INTO public."schema_migrations" (version) VALUES (20200727180623);
INSERT INTO public."schema_migrations" (version) VALUES (20200826081727);
INSERT INTO public."schema_migrations" (version) VALUES (20200924193405);
INSERT INTO public."schema_migrations" (version) VALUES (20201006113225);
INSERT INTO public."schema_migrations" (version) VALUES (20201013101431);
INSERT INTO public."schema_migrations" (version) VALUES (20201023101018);
INSERT INTO public."schema_migrations" (version) VALUES (20201027171943);
INSERT INTO public."schema_migrations" (version) VALUES (20201028073000);
INSERT INTO public."schema_migrations" (version) VALUES (20201101121212);
INSERT INTO public."schema_migrations" (version) VALUES (20201109045808);
INSERT INTO public."schema_migrations" (version) VALUES (20201109104646);
INSERT INTO public."schema_migrations" (version) VALUES (20201111013043);
INSERT INTO public."schema_migrations" (version) VALUES (20201111063858);
INSERT INTO public."schema_migrations" (version) VALUES (20201113072446);
INSERT INTO public."schema_migrations" (version) VALUES (20201127092412);
INSERT INTO public."schema_migrations" (version) VALUES (20201201143144);
INSERT INTO public."schema_migrations" (version) VALUES (20201207123324);
INSERT INTO public."schema_migrations" (version) VALUES (20201214124257);
INSERT INTO public."schema_migrations" (version) VALUES (20201222120543);
INSERT INTO public."schema_migrations" (version) VALUES (20210106110739);
INSERT INTO public."schema_migrations" (version) VALUES (20210114100139);
INSERT INTO public."schema_migrations" (version) VALUES (20210119132444);
INSERT INTO public."schema_migrations" (version) VALUES (20210121071908);
INSERT INTO public."schema_migrations" (version) VALUES (20210125052414);
INSERT INTO public."schema_migrations" (version) VALUES (20210125060448);
INSERT INTO public."schema_migrations" (version) VALUES (20210130040741);
INSERT INTO public."schema_migrations" (version) VALUES (20210201172459);
INSERT INTO public."schema_migrations" (version) VALUES (20210203172842);
INSERT INTO public."schema_migrations" (version) VALUES (20210210023539);
INSERT INTO public."schema_migrations" (version) VALUES (20210218003423);
INSERT INTO public."schema_migrations" (version) VALUES (20210218084225);
INSERT INTO public."schema_migrations" (version) VALUES (20210220013242);
INSERT INTO public."schema_migrations" (version) VALUES (20210225083751);
INSERT INTO public."schema_migrations" (version) VALUES (20210308092147);
INSERT INTO public."schema_migrations" (version) VALUES (20210316195915);
INSERT INTO public."schema_migrations" (version) VALUES (20210321001630);
INSERT INTO public."schema_migrations" (version) VALUES (20210322182605);
INSERT INTO public."schema_migrations" (version) VALUES (20210324073555);
INSERT INTO public."schema_migrations" (version) VALUES (20210325044923);
INSERT INTO public."schema_migrations" (version) VALUES (20210326234327);
INSERT INTO public."schema_migrations" (version) VALUES (20210406052407);
INSERT INTO public."schema_migrations" (version) VALUES (20210409045013);
INSERT INTO public."schema_migrations" (version) VALUES (20210417014050);
INSERT INTO public."schema_migrations" (version) VALUES (20210417183726);
INSERT INTO public."schema_migrations" (version) VALUES (20210417224300);
INSERT INTO public."schema_migrations" (version) VALUES (20210418014629);
INSERT INTO public."schema_migrations" (version) VALUES (20210423062238);
INSERT INTO public."schema_migrations" (version) VALUES (20210501222848);
INSERT INTO public."schema_migrations" (version) VALUES (20210511080620);
INSERT INTO public."schema_migrations" (version) VALUES (20210517055305);
INSERT INTO public."schema_migrations" (version) VALUES (20210521112227);
INSERT INTO public."schema_migrations" (version) VALUES (20210526083141);
INSERT INTO public."schema_migrations" (version) VALUES (20210527125035);
INSERT INTO public."schema_migrations" (version) VALUES (20210610093045);
INSERT INTO public."schema_migrations" (version) VALUES (20210616074312);
INSERT INTO public."schema_migrations" (version) VALUES (20210630101412);
INSERT INTO public."schema_migrations" (version) VALUES (20210707060535);
INSERT INTO public."schema_migrations" (version) VALUES (20210722094027);
INSERT INTO public."schema_migrations" (version) VALUES (20210806092436);
INSERT INTO public."schema_migrations" (version) VALUES (20210817103124);
INSERT INTO public."schema_migrations" (version) VALUES (20210915070956);
INSERT INTO public."schema_migrations" (version) VALUES (20210920042723);
INSERT INTO public."schema_migrations" (version) VALUES (20210921164609);
INSERT INTO public."schema_migrations" (version) VALUES (20210930102613);
INSERT INTO public."schema_migrations" (version) VALUES (20211026123120);
INSERT INTO public."schema_migrations" (version) VALUES (20211124063048);
INSERT INTO public."schema_migrations" (version) VALUES (20211129114942);
INSERT INTO public."schema_migrations" (version) VALUES (20211129193305);
INSERT INTO public."schema_migrations" (version) VALUES (20211130120043);
INSERT INTO public."schema_migrations" (version) VALUES (20211222095004);
INSERT INTO public."schema_migrations" (version) VALUES (20220103194517);
INSERT INTO public."schema_migrations" (version) VALUES (20220105070545);
INSERT INTO public."schema_migrations" (version) VALUES (20220107123528);
INSERT INTO public."schema_migrations" (version) VALUES (20220111122456);
INSERT INTO public."schema_migrations" (version) VALUES (20220125085553);
INSERT INTO public."schema_migrations" (version) VALUES (20220129095329);
INSERT INTO public."schema_migrations" (version) VALUES (20220211220835);
INSERT INTO public."schema_migrations" (version) VALUES (20220216151507);
INSERT INTO public."schema_migrations" (version) VALUES (20220217210850);
INSERT INTO public."schema_migrations" (version) VALUES (20220228100913);
INSERT INTO public."schema_migrations" (version) VALUES (20220314060653);
INSERT INTO public."schema_migrations" (version) VALUES (20220328113810);
INSERT INTO public."schema_migrations" (version) VALUES (20220331123334);
INSERT INTO public."schema_migrations" (version) VALUES (20220421053535);
INSERT INTO public."schema_migrations" (version) VALUES (20220509103325);
INSERT INTO public."schema_migrations" (version) VALUES (20220606122101);
INSERT INTO public."schema_migrations" (version) VALUES (20220609073705);
INSERT INTO public."schema_migrations" (version) VALUES (20220614095610);
INSERT INTO public."schema_migrations" (version) VALUES (20220615045615);
INSERT INTO public."schema_migrations" (version) VALUES (20220616055250);
INSERT INTO public."schema_migrations" (version) VALUES (20220725085345);
INSERT INTO public."schema_migrations" (version) VALUES (20220804173617);
INSERT INTO public."schema_migrations" (version) VALUES (20220823091156);
INSERT INTO public."schema_migrations" (version) VALUES (20220826061242);
INSERT INTO public."schema_migrations" (version) VALUES (20220905054418);
INSERT INTO public."schema_migrations" (version) VALUES (20220906140729);
INSERT INTO public."schema_migrations" (version) VALUES (20220915095949);
INSERT INTO public."schema_migrations" (version) VALUES (20220929062917);
INSERT INTO public."schema_migrations" (version) VALUES (20221011082819);
INSERT INTO public."schema_migrations" (version) VALUES (20221012062208);
INSERT INTO public."schema_migrations" (version) VALUES (20221013081740);
INSERT INTO public."schema_migrations" (version) VALUES (20221108092656);
INSERT INTO public."schema_migrations" (version) VALUES (20221125132509);
INSERT INTO public."schema_migrations" (version) VALUES (20221130112021);
INSERT INTO public."schema_migrations" (version) VALUES (20221202103552);
INSERT INTO public."schema_migrations" (version) VALUES (20221223030323);
INSERT INTO public."schema_migrations" (version) VALUES (20230104054512);
INSERT INTO public."schema_migrations" (version) VALUES (20230131111743);
INSERT INTO public."schema_migrations" (version) VALUES (20230202072241);
INSERT INTO public."schema_migrations" (version) VALUES (20230314073042);
INSERT INTO public."schema_migrations" (version) VALUES (20230316080512);
INSERT INTO public."schema_migrations" (version) VALUES (20230403001516);
INSERT INTO public."schema_migrations" (version) VALUES (20230408024016);
INSERT INTO public."schema_migrations" (version) VALUES (20230502060609);
INSERT INTO public."schema_migrations" (version) VALUES (20230507220819);
INSERT INTO public."schema_migrations" (version) VALUES (20230512175955);
INSERT INTO public."schema_migrations" (version) VALUES (20230522105210);
INSERT INTO public."schema_migrations" (version) VALUES (20230616045651);
INSERT INTO public."schema_migrations" (version) VALUES (20230627145331);
INSERT INTO public."schema_migrations" (version) VALUES (20230710133911);
INSERT INTO public."schema_migrations" (version) VALUES (20230725091729);
INSERT INTO public."schema_migrations" (version) VALUES (20230725091730);
INSERT INTO public."schema_migrations" (version) VALUES (20230801091505);
INSERT INTO public."schema_migrations" (version) VALUES (20230803115906);
INSERT INTO public."schema_migrations" (version) VALUES (20230810180931);
INSERT INTO public."schema_migrations" (version) VALUES (20230814065215);
INSERT INTO public."schema_migrations" (version) VALUES (20230818012026);
INSERT INTO public."schema_migrations" (version) VALUES (20230818114410);
INSERT INTO public."schema_migrations" (version) VALUES (20230820104852);
INSERT INTO public."schema_migrations" (version) VALUES (20230909123216);
INSERT INTO public."schema_migrations" (version) VALUES (20231118000016);
INSERT INTO public."schema_migrations" (version) VALUES (20231122115923);
INSERT INTO public."schema_migrations" (version) VALUES (20240117234740);
INSERT INTO public."schema_migrations" (version) VALUES (20240220134922);
INSERT INTO public."schema_migrations" (version) VALUES (20240222064744);
INSERT INTO public."schema_migrations" (version) VALUES (20240229113537);
INSERT INTO public."schema_migrations" (version) VALUES (20240308095004);
INSERT INTO public."schema_migrations" (version) VALUES (20240320135052);
INSERT INTO public."schema_migrations" (version) VALUES (20240422172324);
INSERT INTO public."schema_migrations" (version) VALUES (20240424071508);
INSERT INTO public."schema_migrations" (version) VALUES (20240515113612);
INSERT INTO public."schema_migrations" (version) VALUES (20240527105105);
INSERT INTO public."schema_migrations" (version) VALUES (20240605165834);
INSERT INTO public."schema_migrations" (version) VALUES (20240627071515);
INSERT INTO public."schema_migrations" (version) VALUES (20240703205102);
INSERT INTO public."schema_migrations" (version) VALUES (20240704090400);
INSERT INTO public."schema_migrations" (version) VALUES (20240723061734);
INSERT INTO public."schema_migrations" (version) VALUES (20240910155519);
INSERT INTO public."schema_migrations" (version) VALUES (20240918055424);
INSERT INTO public."schema_migrations" (version) VALUES (20240930061155);
INSERT INTO public."schema_migrations" (version) VALUES (20241115094241);
INSERT INTO public."schema_migrations" (version) VALUES (20241120104539);
INSERT INTO public."schema_migrations" (version) VALUES (20241201163710);
INSERT INTO public."schema_migrations" (version) VALUES (20241205205937);
INSERT INTO public."schema_migrations" (version) VALUES (20241208181710);
INSERT INTO public."schema_migrations" (version) VALUES (20241209091320);
INSERT INTO public."schema_migrations" (version) VALUES (20250106161903);
INSERT INTO public."schema_migrations" (version) VALUES (20250109212933);
INSERT INTO public."schema_migrations" (version) VALUES (20250109213637);
INSERT INTO public."schema_migrations" (version) VALUES (20250224062928);
INSERT INTO public."schema_migrations" (version) VALUES (20250227212728);
INSERT INTO public."schema_migrations" (version) VALUES (20250405133306);
INSERT INTO public."schema_migrations" (version) VALUES (20250407174642);
INSERT INTO public."schema_migrations" (version) VALUES (20250520100142);
INSERT INTO public."schema_migrations" (version) VALUES (20250520120237);
INSERT INTO public."schema_migrations" (version) VALUES (20250529164649);
INSERT INTO public."schema_migrations" (version) VALUES (20250618124706);
INSERT INTO public."schema_migrations" (version) VALUES (20250711055838);
INSERT INTO public."schema_migrations" (version) VALUES (20250715000000);
INSERT INTO public."schema_migrations" (version) VALUES (20250716033709);
INSERT INTO public."schema_migrations" (version) VALUES (20250814023042);
INSERT INTO public."schema_migrations" (version) VALUES (20250826070711);
INSERT INTO public."schema_migrations" (version) VALUES (20250910093925);
INSERT INTO public."schema_migrations" (version) VALUES (20251016171923);
INSERT INTO public."schema_migrations" (version) VALUES (20251021100612);
INSERT INTO public."schema_migrations" (version) VALUES (20251027070958);
INSERT INTO public."schema_migrations" (version) VALUES (20251105035933);
INSERT INTO public."schema_migrations" (version) VALUES (20251110073502);
INSERT INTO public."schema_migrations" (version) VALUES (20251112051450);
INSERT INTO public."schema_migrations" (version) VALUES (20251112165155);
INSERT INTO public."schema_migrations" (version) VALUES (20251112165327);
INSERT INTO public."schema_migrations" (version) VALUES (20251204052359);
INSERT INTO public."schema_migrations" (version) VALUES (20251204053043);
INSERT INTO public."schema_migrations" (version) VALUES (20251204053335);
INSERT INTO public."schema_migrations" (version) VALUES (20251207180524);
INSERT INTO public."schema_migrations" (version) VALUES (20251223101825);
INSERT INTO public."schema_migrations" (version) VALUES (20260120120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260213110822);
INSERT INTO public."schema_migrations" (version) VALUES (20260219120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260304000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260309111112);
INSERT INTO public."schema_migrations" (version) VALUES (20260310161544);
INSERT INTO public."schema_migrations" (version) VALUES (20260317000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260322120000);
INSERT INTO public."schema_migrations" (version) VALUES (20260325000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260401000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260429150747);
INSERT INTO public."schema_migrations" (version) VALUES (20260429213725);
INSERT INTO public."schema_migrations" (version) VALUES (20260504072827);
INSERT INTO public."schema_migrations" (version) VALUES (20260507000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260511000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260513000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260513140000);
INSERT INTO public."schema_migrations" (version) VALUES (20260513140100);
INSERT INTO public."schema_migrations" (version) VALUES (20260513140200);
INSERT INTO public."schema_migrations" (version) VALUES (20260617054815);
INSERT INTO public."schema_migrations" (version) VALUES (20260619000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260623000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260703000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260706000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260715000000);
INSERT INTO public."schema_migrations" (version) VALUES (20260715085249);
INSERT INTO public."schema_migrations" (version) VALUES (20260715085302);
INSERT INTO public."schema_migrations" (version) VALUES (20260716092134);
INSERT INTO public."schema_migrations" (version) VALUES (20260812154401);
INSERT INTO public."schema_migrations" (version) VALUES (20260812154402);
INSERT INTO public."schema_migrations" (version) VALUES (20260813155534);
