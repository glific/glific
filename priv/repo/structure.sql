--
-- PostgreSQL database dump
--
-- Dumped from database version 15.3 (Homebrew)
-- Dumped by pg_dump version 15.3 (Homebrew)
SET statement_timeout = 0;

SET lock_timeout = 0;

SET idle_in_transaction_session_timeout = 0;

SET client_encoding = 'UTF8';

SET standard_conforming_strings = ON;

SELECT
  pg_catalog.SET_CONFIG('search_path', '', FALSE);

SET check_function_bodies = FALSE;

SET xmloption = content;

SET client_min_messages = warning;

SET row_security = OFF;

--
-- Name: global; Type: SCHEMA; Schema: -; Owner: -
--
CREATE SCHEMA global;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--
-- *not* creating schema, since initdb creates it
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
  'scheduled',
  'executing',
  'retryable',
  'completed',
  'discarded',
  'cancelled'
);

--
-- Name: api_status_enum; Type: TYPE; Schema: public; Owner: -
--
CREATE TYPE public.api_status_enum AS ENUM (
  'ok',
  'error'
);

--
-- Name: contact_field_scope_enum; Type: TYPE; Schema: public; Owner: -
--
CREATE TYPE public.contact_field_scope_enum AS ENUM (
  'contact',
  'globals'
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
  'message'
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
  'quick_reply'
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
  'contact_opt_out'
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
  'sticker'
);

--
-- Name: organization_status_enum; Type: TYPE; Schema: public; Owner: -
--
CREATE TYPE public.organization_status_enum AS ENUM (
  'inactive',
  'approved',
  'active',
  'suspended',
  'ready_to_delete'
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
  'quick_reply'
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
-- Name: oban_jobs_notify(); Type: FUNCTION; Schema: global; Owner: -
--
CREATE FUNCTION global.oban_jobs_notify ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
DECLARE
  channel text;
  notice json;
BEGIN
  IF NEW.state = 'available' THEN
    channel = 'global.oban_insert';
    notice = JSON_BUILD_OBJECT('queue', NEW.queue);
    PERFORM
      PG_NOTIFY(channel, notice::text);
  END IF;
  RETURN NULL;
END;
$$;

--
-- Name: message_after_insert_callback(); Type: FUNCTION; Schema: public; Owner: -
--
CREATE FUNCTION public.message_after_insert_callback ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
DECLARE
  session_lim bigint;
  DECLARE current_diff bigint;
  DECLARE current_session_uuid uuid;
  DECLARE session_uuid_value uuid;
  DECLARE var_message_at timestamp with time zone;
BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  UPDATE
    organizations
  SET
    last_communication_at = (CURRENT_TIMESTAMP at time zone 'utc')
  WHERE
    id = NEW.organization_id;
  IF (NEW.flow = 'inbound') THEN
    SELECT
      session_limit * 60 INTO session_lim
    FROM
      organizations
    WHERE
      id = NEW.organization_id
    LIMIT 1;
    SELECT
      EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) - EXTRACT(EPOCH FROM var_message_at) INTO current_diff;
    SELECT
      session_uuid INTO current_session_uuid
    FROM
      messages
    WHERE
      contact_id = NEW.contact_id
      AND organization_id = NEW.organization_id
      AND flow = 'inbound'
      AND id != NEW.id
    ORDER BY
      id DESC
    LIMIT 1;
    IF (current_diff < session_lim AND current_session_uuid IS NOT NULL) THEN
      session_uuid_value = current_session_uuid;
    ELSE
      session_uuid_value = (
        SELECT
          uuid_generate_v4 ());
    END IF;
    UPDATE
      messages
    SET
      session_uuid = session_uuid_value
    WHERE
      id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

--
-- Name: message_before_insert_callback(); Type: FUNCTION; Schema: public; Owner: -
--
CREATE FUNCTION public.message_before_insert_callback ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
DECLARE
  now timestamp with time zone;
  DECLARE var_message_number bigint;
  DECLARE var_profile_id bigint;
  DECLARE var_context_id bigint;
BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  IF (TG_OP = 'INSERT') THEN
    now := (CURRENT_TIMESTAMP at time zone 'utc');
    IF (NEW.sender_id = NEW.receiver_id AND NEW.group_id > 0) THEN
      SELECT
        last_message_number INTO var_message_number
      FROM
        GROUPS
      WHERE
        id = NEW.group_id
      LIMIT 1;
      IF (var_message_number IS NULL) THEN
        var_message_number = 0;
      END IF;
      var_message_number = var_message_number + 1;
      UPDATE
        GROUPS
      SET
        last_communication_at = now,
        last_message_number = var_message_number
      WHERE
        id = NEW.group_id;
      NEW.message_number = var_message_number;
    ELSE
      SELECT
        last_message_number,
        active_profile_id INTO var_message_number,
        var_profile_id
      FROM
        contacts
      WHERE
        organization_id = NEW.organization_id
        AND id = NEW.contact_id
      LIMIT 1;
      NEW.profile_id = var_profile_id;
      var_message_number = var_message_number + 1;
      IF (NEW.flow = 'inbound') THEN
        IF (NEW.context_id IS NOT NULL) THEN
          SELECT
            id INTO var_context_id
          FROM
            messages
          WHERE
            bsp_message_id = NEW.context_id;
          NEW.context_message_id = var_context_id;
        END IF;
        UPDATE
          contacts
        SET
          last_communication_at = now,
          last_message_at = now,
          last_message_number = var_message_number,
          is_org_read = FALSE,
          is_org_replied = FALSE,
          is_contact_replied = TRUE,
          updated_at = now
        WHERE
          id = NEW.contact_id;
      ELSE
        UPDATE
          contacts
        SET
          last_communication_at = now,
          last_message_number = var_message_number,
          is_org_replied = TRUE,
          is_contact_replied = FALSE,
          updated_at = now
        WHERE
          id = NEW.contact_id;
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
CREATE FUNCTION public.remove_old_history ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
BEGIN
  WITH ranked AS (
    SELECT
      id,
      ROW_NUMBER() OVER (PARTITION BY contact_id ORDER BY updated_at DESC) AS rn
    FROM
      contact_histories
    WHERE
      id <> NEW.id
      AND contact_id = NEW.contact_id)
  DELETE FROM contact_histories
  WHERE id IN (
      SELECT
        id
      FROM
        ranked
      WHERE
        rn >= 25);
  RETURN NEW;
END;
$$;

--
-- Name: update_contact_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--
CREATE FUNCTION public.update_contact_updated_at ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    UPDATE
      contacts
    SET
      updated_at = (CURRENT_TIMESTAMP at time zone 'utc')
    WHERE
      id = NEW.contact_id;
  ELSE
    IF (TG_OP = 'DELETE') THEN
      UPDATE
        contacts
      SET
        updated_at = (CURRENT_TIMESTAMP at time zone 'utc')
      WHERE
        id = OLD.contact_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

--
-- Name: update_contact_updated_at_on_tagging(); Type: FUNCTION; Schema: public; Owner: -
--
CREATE FUNCTION public.update_contact_updated_at_on_tagging ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    UPDATE
      contacts
    SET
      updated_at = (CURRENT_TIMESTAMP at time zone 'utc')
    WHERE
      id = NEW.contact_id;
  ELSE
    IF (TG_OP = 'DELETE') THEN
      UPDATE
        contacts
      SET
        updated_at = (CURRENT_TIMESTAMP at time zone 'utc')
      WHERE
        id = OLD.contact_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

--
-- Name: update_flow_revision_number(); Type: FUNCTION; Schema: public; Owner: -
--
CREATE FUNCTION public.update_flow_revision_number ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    UPDATE
      flow_revisions
    SET
      revision_number = revision_number + 1
    WHERE
      flow_id = NEW.flow_id
      AND id < NEW.id;
    RETURN NEW;
  END IF;
  RETURN NULL;
END;
$$;

--
-- Name: update_message_number(); Type: FUNCTION; Schema: public; Owner: -
--
CREATE FUNCTION public.update_message_number ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
DECLARE
  message_ids bigint[];
  DECLARE session_lim bigint;
  DECLARE current_diff bigint;
  DECLARE current_session_uuid uuid;
  DECLARE session_uuid_value uuid;
  DECLARE now timestamp with time zone;
  DECLARE var_message_at timestamp with time zone;
  DECLARE var_message_number bigint;
  DECLARE var_context_id bigint;
BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  IF (TG_OP = 'INSERT') THEN
    now := (CURRENT_TIMESTAMP at time zone 'utc');
    UPDATE
      organizations
    SET
      last_communication_at = now
    WHERE
      id = NEW.organization_id;
    IF (NEW.group_id > 0 AND NEW.sender_id = NEW.receiver_id) THEN
      SELECT
        last_message_number INTO var_message_number
      FROM
        GROUPS
      WHERE
        id = NEW.group_id
      LIMIT 1;
      IF (var_message_number IS NULL) THEN
        var_message_number = 0;
      END IF;
      NEW.message_number = var_message_number + 1;
      UPDATE
        GROUPS
      SET
        last_communication_at = now,
        last_message_number = last_message_number + 1
      WHERE
        id = NEW.group_id;
    ELSE
      SELECT
        last_message_number,
        last_message_at INTO var_message_number,
        var_message_at
      FROM
        contacts
      WHERE
        id = NEW.contact_id
        AND organization_id = NEW.organization_id
      LIMIT 1;
      IF (NEW.flow = 'inbound') THEN
        SELECT
          session_limit * 60 INTO session_lim
        FROM
          organizations
        WHERE
          id = NEW.organization_id
        LIMIT 1;
        SELECT
          EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) - EXTRACT(EPOCH FROM var_message_at) INTO current_diff;
        SELECT
          session_uuid INTO current_session_uuid
        FROM
          messages
        WHERE
          contact_id = NEW.contact_id
          AND organization_id = NEW.organization_id
          AND flow = 'inbound'
          AND id != NEW.id
        ORDER BY
          id DESC
        LIMIT 1;
        IF (current_diff < session_lim AND current_session_uuid IS NOT NULL) THEN
          session_uuid_value = current_session_uuid;
        ELSE
          session_uuid_value = (
            SELECT
              uuid_generate_v4 ());
        END IF;
        UPDATE
          contacts
        SET
          last_communication_at = now,
          last_message_at = now,
          last_message_number = var_message_number + 1,
          is_org_read = FALSE,
          is_org_replied = FALSE,
          is_contact_replied = TRUE,
          updated_at = now
        WHERE
          id = NEW.contact_id;
        IF (NEW.context_id IS NOT NULL) THEN
          SELECT
            id INTO var_context_id
          FROM
            messages
          WHERE
            bsp_message_id = NEW.context_id;
          NEW.context_message_id = var_context_id;
        END IF;
        NEW.message_number = var_message_number + 1;
        NEW.session_uuid = session_uuid_value;
      ELSE
        UPDATE
          contacts
        SET
          last_communication_at = now,
          last_message_number = var_message_number + 1,
          is_org_replied = TRUE,
          is_contact_replied = FALSE,
          updated_at = now
        WHERE
          id = NEW.contact_id;
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
CREATE FUNCTION public.update_message_updated_at ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    UPDATE
      messages
    SET
      updated_at = (CURRENT_TIMESTAMP at time zone 'utc')
    WHERE
      id = NEW.message_id;
  ELSE
    IF (TG_OP = 'DELETE') THEN
      UPDATE
        messages
      SET
        updated_at = (CURRENT_TIMESTAMP at time zone 'utc')
      WHERE
        id = OLD.message_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

--
-- Name: update_organization_id(); Type: FUNCTION; Schema: public; Owner: -
--
CREATE FUNCTION public.update_organization_id ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
BEGIN
  UPDATE
    organizations
  SET
    organization_id = id;
  RETURN NULL;
END;
$$;

--
-- Name: update_profile_id_on_new_contact_history(); Type: FUNCTION; Schema: public; Owner: -
--
CREATE FUNCTION public.update_profile_id_on_new_contact_history ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  IF (TG_OP = 'INSERT') THEN
    UPDATE
      contact_histories
    SET
      profile_id = (
        SELECT
          active_profile_id
        FROM
          contacts
        WHERE
          id = NEW.contact_id)
    WHERE
      id = NEW.id;
  END IF;
  RETURN NULL;
END;
$$;

--
-- Name: update_profile_id_on_new_flow_context(); Type: FUNCTION; Schema: public; Owner: -
--
CREATE FUNCTION public.update_profile_id_on_new_flow_context ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  IF (TG_OP = 'INSERT') THEN
    UPDATE
      flow_contexts
    SET
      profile_id = (
        SELECT
          active_profile_id
        FROM
          contacts
        WHERE
          id = NEW.contact_id)
    WHERE
      id = NEW.id;
  END IF;
  RETURN NULL;
END;
$$;

--
-- Name: update_profile_id_on_new_flow_result(); Type: FUNCTION; Schema: public; Owner: -
--
CREATE FUNCTION public.update_profile_id_on_new_flow_result ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  IF (TG_OP = 'INSERT') THEN
    UPDATE
      flow_results
    SET
      profile_id = (
        SELECT
          active_profile_id
        FROM
          contacts
        WHERE
          id = NEW.contact_id)
    WHERE
      id = NEW.id;
  END IF;
  RETURN NULL;
END;
$$;

--
-- Name: update_profile_id_on_new_message(); Type: FUNCTION; Schema: public; Owner: -
--
CREATE FUNCTION public.update_profile_id_on_new_message ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  UPDATE
    messages
  SET
    profile_id = (
      SELECT
        active_profile_id
      FROM
        contacts
      WHERE
        id = NEW.contact_id)
  WHERE
    id = NEW.id;
  RETURN NULL;
END;
$$;

--
-- Name: update_tag_ancestors(); Type: FUNCTION; Schema: public; Owner: -
--
CREATE FUNCTION public.update_tag_ancestors ()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  AS $$
BEGIN
  WITH RECURSIVE parents AS (
    SELECT
      id AS id,
      ARRAY[id] AS ancestry
    FROM
      tags
    WHERE
      parent_id IS NULL
    UNION
    SELECT
      child.id AS id,
      ARRAY_APPEND(p.ancestry, child.id) AS ancestry
    FROM
      tags child
      INNER JOIN parents p ON p.id = child.parent_id)
  UPDATE
    tags
  SET
    ancestors = (
      SELECT
        ARRAY_REMOVE(parents.ancestry, tags.id) AS ancestry
      FROM
        parents
      WHERE
        parents.id = tags.id);
  RETURN NULL;
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
  is_active boolean DEFAULT TRUE,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  localized boolean DEFAULT FALSE
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
-- Name: oban_jobs; Type: TABLE; Schema: global; Owner: -
--
CREATE TABLE global.oban_jobs (
  id bigint NOT NULL,
  state global.oban_job_state DEFAULT 'available' ::global.oban_job_state NOT NULL,
  queue text DEFAULT 'default' ::text NOT NULL,
  worker text NOT NULL,
  args jsonb DEFAULT '{}' ::jsonb NOT NULL,
  errors jsonb[] DEFAULT ARRAY[] ::jsonb[] NOT NULL,
  attempt integer DEFAULT 0 NOT NULL,
  max_attempts integer DEFAULT 20 NOT NULL,
  inserted_at timestamp without time zone DEFAULT TIMEZONE('UTC'::text, NOW()) NOT NULL,
  scheduled_at timestamp without time zone DEFAULT TIMEZONE('UTC'::text, NOW()) NOT NULL,
  attempted_at timestamp without time zone,
  completed_at timestamp without time zone,
  attempted_by text[],
  discarded_at timestamp without time zone,
  priority integer DEFAULT 0 NOT NULL,
  tags character varying(255)[] DEFAULT ARRAY[] ::character varying[],
  meta jsonb DEFAULT '{}' ::jsonb,
  cancelled_at timestamp without time zone,
  CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
  CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
  CONSTRAINT priority_range CHECK (((priority >= 0) AND (priority <= 3))),
  CONSTRAINT queue_length CHECK (((CHAR_LENGTH(queue) > 0) AND (CHAR_LENGTH(queue) < 128))),
  CONSTRAINT worker_length CHECK (((CHAR_LENGTH(worker) > 0) AND (CHAR_LENGTH(worker) < 128)))
);

--
-- Name: TABLE oban_jobs; Type: COMMENT; Schema: global; Owner: -
--
COMMENT ON TABLE global.oban_jobs IS '11';

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
  meta jsonb DEFAULT '{}' ::jsonb NOT NULL,
  started_at timestamp without time zone DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  updated_at timestamp without time zone DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
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
  is_required boolean DEFAULT FALSE,
  keys jsonb DEFAULT '{}' ::jsonb,
  secrets jsonb DEFAULT '{}' ::jsonb,
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
-- Name: bigquery_jobs; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.bigquery_jobs (
  id bigint NOT NULL,
  "table" character varying(255),
  table_id integer,
  organization_id bigint NOT NULL,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  last_updated_at timestamp without time zone
);

--
-- Name: COLUMN bigquery_jobs."table"; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.bigquery_jobs. "table" IS 'Table name';

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
  stripe_subscription_items jsonb DEFAULT '{}' ::jsonb,
  stripe_current_period_start timestamp(0) without time zone,
  stripe_current_period_end timestamp(0) without time zone,
  stripe_last_usage_recorded timestamp(0) without time zone,
  name character varying(255),
  email character varying(255),
  currency character varying(255),
  is_delinquent boolean,
  is_active boolean DEFAULT TRUE,
  organization_id bigint NOT NULL,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  deduct_tds boolean DEFAULT FALSE,
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
  is_billable boolean DEFAULT TRUE,
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
COMMENT ON COLUMN public.consulting_hours. "when" IS 'Date and time of when the support call happened';

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
  event_meta jsonb DEFAULT '{}' ::jsonb,
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
  bsp_status public.contact_provider_status_enum DEFAULT 'none' ::public.contact_provider_status_enum NOT NULL,
  status public.contact_status_enum DEFAULT 'valid' ::public.contact_status_enum NOT NULL,
  language_id bigint NOT NULL,
  optin_time timestamp(0) without time zone,
  optout_time timestamp(0) without time zone,
  last_message_at timestamp(0) without time zone,
  settings jsonb DEFAULT '{}' ::jsonb,
  fields jsonb DEFAULT '{}' ::jsonb,
  organization_id bigint NOT NULL,
  inserted_at timestamp without time zone NOT NULL,
  updated_at timestamp without time zone NOT NULL,
  last_communication_at timestamp(0) without time zone,
  optin_method character varying(255),
  optin_status boolean DEFAULT FALSE,
  optin_message_id character varying(255),
  is_org_read boolean DEFAULT TRUE,
  is_org_replied boolean DEFAULT TRUE,
  is_contact_replied boolean DEFAULT TRUE,
  last_message_number integer DEFAULT 0,
  optout_method character varying(255),
  active_profile_id bigint
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
  inserted_at timestamp(0) without time zone DEFAULT '2021-01-01 00:00:00' ::timestamp without time zone NOT NULL,
  updated_at timestamp(0) without time zone DEFAULT '2021-01-01 00:00:00' ::timestamp without time zone NOT NULL
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
-- Name: credentials; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.credentials (
  id bigint NOT NULL,
  keys jsonb DEFAULT '{}' ::jsonb,
  secrets bytea,
  is_active boolean DEFAULT FALSE,
  is_valid boolean DEFAULT TRUE,
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
  is_valid boolean DEFAULT FALSE,
  is_active boolean DEFAULT TRUE,
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
  updated_at timestamp(0) without time zone NOT NULL
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
  default_results jsonb
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
  contact_id bigint NOT NULL,
  flow_id bigint NOT NULL,
  results jsonb DEFAULT '{}' ::jsonb,
  parent_id bigint,
  wakeup_at timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
  completed_at timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
  recent_inbound jsonb DEFAULT '[]' ::jsonb,
  recent_outbound jsonb DEFAULT '[]' ::jsonb,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  status character varying(255) DEFAULT 'published' ::character varying,
  organization_id bigint NOT NULL,
  is_background_flow boolean DEFAULT FALSE,
  group_message_id bigint,
  message_broadcast_id bigint,
  is_await_result boolean DEFAULT FALSE,
  is_killed boolean DEFAULT FALSE,
  profile_id bigint,
  reason character varying(255)
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
  recent_messages jsonb[] DEFAULT ARRAY[] ::jsonb[],
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
  results jsonb DEFAULT '{}' ::jsonb,
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
  status character varying(255) DEFAULT 'draft' ::character varying,
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
  version_number character varying(255) DEFAULT '13.1.0' ::character varying,
  flow_type public.flow_type_enum DEFAULT 'message' ::public.flow_type_enum NOT NULL,
  ignore_keywords boolean DEFAULT FALSE,
  keywords character varying(255)[] DEFAULT ARRAY[] ::character varying[],
  organization_id bigint NOT NULL,
  inserted_at timestamp without time zone NOT NULL,
  updated_at timestamp without time zone NOT NULL,
  respond_other boolean DEFAULT FALSE,
  respond_no_response boolean DEFAULT FALSE,
  is_active boolean DEFAULT TRUE,
  is_background boolean DEFAULT FALSE,
  is_pinned boolean DEFAULT FALSE,
  tag_id bigint
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
  updated_at timestamp(0) without time zone NOT NULL
);

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
  is_restricted boolean DEFAULT FALSE,
  organization_id bigint NOT NULL,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  last_communication_at timestamp(0) without time zone,
  last_message_number integer DEFAULT 0
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
  interactive_content jsonb DEFAULT '[]' ::jsonb,
  organization_id bigint,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  translations jsonb DEFAULT '{}' ::jsonb,
  language_id bigint DEFAULT 1 NOT NULL,
  send_with_title boolean DEFAULT TRUE NOT NULL,
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
  line_items jsonb DEFAULT '{}' ::jsonb,
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
-- Name: locations; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.locations (
  id bigint NOT NULL,
  contact_id bigint NOT NULL,
  message_id bigint NOT NULL,
  longitude double precision NOT NULL,
  latitude double precision NOT NULL,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  organization_id bigint NOT NULL
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
  status character varying(255) DEFAULT 'pending' ::character varying NOT NULL,
  error character varying(255),
  content jsonb DEFAULT '{}' ::jsonb,
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
  is_hsm boolean DEFAULT FALSE,
  flow public.message_flow_enum,
  status public.message_status_enum DEFAULT 'enqueued' ::public.message_status_enum NOT NULL,
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
  interactive_content jsonb DEFAULT '{}' ::jsonb,
  group_message_id bigint,
  template_id bigint,
  interactive_template_id bigint,
  message_broadcast_id bigint,
  profile_id bigint
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
  is_billable boolean DEFAULT FALSE,
  message_id bigint,
  organization_id bigint NOT NULL,
  payload jsonb DEFAULT '{}' ::jsonb,
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
  provider_media_id character varying(255),
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  gcs_url text,
  organization_id bigint NOT NULL,
  content_type character varying(255)
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
-- Name: COLUMN messages_media.provider_media_id; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.messages_media.provider_media_id IS 'Whatsapp message ID';

--
-- Name: COLUMN messages_media.content_type; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.messages_media.content_type IS 'Content Type for the media message sent by WABA';

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
  entity jsonb DEFAULT '{}' ::jsonb,
  category character varying(255),
  message text,
  severity text DEFAULT 'Error' ::text,
  organization_id bigint NOT NULL,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  is_read boolean DEFAULT FALSE
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
  json jsonb DEFAULT '{}' ::jsonb,
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
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.organizations (
  id bigint NOT NULL,
  name character varying(255) NOT NULL,
  shortcode character varying(255) NOT NULL,
  email character varying(255) NOT NULL,
  bsp_id bigint NOT NULL,
  default_language_id bigint NOT NULL,
  active_language_ids integer[] DEFAULT ARRAY[] ::integer[],
  contact_id integer,
  out_of_office jsonb,
  is_active boolean DEFAULT TRUE,
  timezone character varying(255),
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  session_limit integer DEFAULT 60,
  organization_id bigint,
  signature_phrase bytea,
  last_communication_at timestamp(0) without time zone,
  is_approved boolean DEFAULT FALSE,
  fields jsonb DEFAULT '{}' ::jsonb,
  status public.organization_status_enum DEFAULT 'inactive' ::public.organization_status_enum,
  newcontact_flow_id bigint,
  is_suspended boolean DEFAULT FALSE,
  suspended_until timestamp(0) without time zone,
  regx_flow jsonb,
  optin_flow_id bigint
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
  type character varying(255)
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
  is_reserved boolean DEFAULT FALSE NOT NULL,
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
  stripe_ids jsonb DEFAULT '[]' ::jsonb,
  tax_rates jsonb DEFAULT '[]' ::jsonb,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  email character varying(255),
  isv_credentials jsonb DEFAULT '{}' ::jsonb
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
  is_reserved boolean DEFAULT FALSE,
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
  tenant character varying(255) DEFAULT 'main' ::character varying NOT NULL,
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
  is_reserved boolean DEFAULT FALSE,
  is_active boolean DEFAULT TRUE,
  is_source boolean DEFAULT FALSE,
  shortcode character varying(255),
  is_hsm boolean DEFAULT FALSE,
  number_parameters integer,
  language_id bigint NOT NULL,
  parent_id bigint,
  message_media_id bigint,
  organization_id bigint NOT NULL,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  translations jsonb DEFAULT '{}' ::jsonb,
  status character varying(255),
  category character varying(255),
  example text,
  has_buttons boolean DEFAULT FALSE,
  button_type public.template_button_type_enum,
  buttons jsonb DEFAULT '[]' ::jsonb,
  bsp_id character varying(255),
  reason character varying(255),
  tag_id bigint
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
  is_active boolean DEFAULT TRUE,
  last_synced_at timestamp(0) without time zone DEFAULT NOW(),
  organization_id bigint NOT NULL,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  sheet_data_count integer,
  type character varying(255)
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
-- Name: sheets_data; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.sheets_data (
  id bigint NOT NULL,
  key character varying(255) NOT NULL,
  row_data jsonb DEFAULT '{}' ::jsonb,
  last_synced_at timestamp(0) without time zone DEFAULT NOW(),
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
  updated_at timestamp(0) without time zone NOT NULL
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
  is_active boolean DEFAULT TRUE,
  is_reserved boolean DEFAULT FALSE,
  ancestors bigint[],
  is_value boolean DEFAULT FALSE,
  keywords character varying(255)[],
  color_code character varying(255) DEFAULT '#0C976D' ::character varying,
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
  body character varying(255),
  topic character varying(255),
  status character varying(255),
  remarks character varying(255),
  contact_id bigint NOT NULL,
  user_id bigint,
  organization_id bigint NOT NULL,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL
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
  trigger_type character varying(255) DEFAULT 'scheduled' ::character varying,
  group_id bigint,
  flow_id bigint,
  start_at timestamp(0) without time zone NOT NULL,
  end_date date,
  last_trigger_at timestamp(0) without time zone,
  next_trigger_at timestamp(0) without time zone,
  is_repeating boolean DEFAULT FALSE,
  frequency character varying(255)[] DEFAULT ARRAY[] ::character varying[],
  days integer[] DEFAULT ARRAY[] ::integer[],
  is_active boolean DEFAULT TRUE,
  organization_id bigint NOT NULL,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  hours integer[] DEFAULT ARRAY[] ::integer[]
);

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
  roles public.user_roles_enum[] DEFAULT ARRAY['none' ::public.user_roles_enum],
  contact_id bigint NOT NULL,
  organization_id bigint NOT NULL,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL,
  is_restricted boolean DEFAULT FALSE,
  last_login_at timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
  last_login_from character varying(255) DEFAULT NULL::character varying,
  language_id bigint,
  upload_contacts boolean DEFAULT FALSE,
  confirmed_at timestamp(0) without time zone
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
-- Name: webhook_logs; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.webhook_logs (
  id bigint NOT NULL,
  url text NOT NULL,
  method text NOT NULL,
  request_headers jsonb DEFAULT '{}' ::jsonb,
  request_json jsonb DEFAULT '{}' ::jsonb,
  response_json jsonb DEFAULT '{}' ::jsonb,
  status_code integer,
  error text,
  flow_id bigint NOT NULL,
  contact_id bigint NOT NULL,
  organization_id bigint NOT NULL,
  inserted_at timestamp(0) without time zone NOT NULL,
  updated_at timestamp(0) without time zone NOT NULL
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
-- Name: fun_with_flags_toggles id; Type: DEFAULT; Schema: global; Owner: -
--
ALTER TABLE ONLY global.fun_with_flags_toggles
  ALTER COLUMN id SET DEFAULT NEXTVAL('global.fun_with_flags_toggles_id_seq'::regclass);

--
-- Name: languages id; Type: DEFAULT; Schema: global; Owner: -
--
ALTER TABLE ONLY global.languages
  ALTER COLUMN id SET DEFAULT NEXTVAL('global.languages_id_seq'::regclass);

--
-- Name: oban_jobs id; Type: DEFAULT; Schema: global; Owner: -
--
ALTER TABLE ONLY global.oban_jobs
  ALTER COLUMN id SET DEFAULT NEXTVAL('global.oban_jobs_id_seq'::regclass);

--
-- Name: permissions id; Type: DEFAULT; Schema: global; Owner: -
--
ALTER TABLE ONLY global.permissions
  ALTER COLUMN id SET DEFAULT NEXTVAL('global.permissions_id_seq'::regclass);

--
-- Name: providers id; Type: DEFAULT; Schema: global; Owner: -
--
ALTER TABLE ONLY global.providers
  ALTER COLUMN id SET DEFAULT NEXTVAL('global.providers_id_seq'::regclass);

--
-- Name: bigquery_jobs id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.bigquery_jobs
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.bigquery_jobs_id_seq'::regclass);

--
-- Name: billings id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.billings
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.billings_id_seq'::regclass);

--
-- Name: consulting_hours id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.consulting_hours
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.consulting_hours_id_seq'::regclass);

--
-- Name: contact_histories id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contact_histories
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.contact_histories_id_seq'::regclass);

--
-- Name: contacts id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.contacts_id_seq'::regclass);

--
-- Name: contacts_fields id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts_fields
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.contacts_fields_id_seq'::regclass);

--
-- Name: contacts_groups id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts_groups
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.contacts_groups_id_seq'::regclass);

--
-- Name: contacts_tags id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts_tags
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.contacts_tags_id_seq'::regclass);

--
-- Name: credentials id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.credentials
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.credentials_id_seq'::regclass);

--
-- Name: extensions id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.extensions
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.extensions_id_seq'::regclass);

--
-- Name: flow_contexts id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_contexts
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.flow_contexts_id_seq'::regclass);

--
-- Name: flow_counts id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_counts
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.flow_counts_id_seq'::regclass);

--
-- Name: flow_labels id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_labels
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.flow_labels_id_seq'::regclass);

--
-- Name: flow_results id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_results
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.flow_results_id_seq'::regclass);

--
-- Name: flow_revisions id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_revisions
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.flow_revisions_id_seq'::regclass);

--
-- Name: flow_roles id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_roles
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.flow_roles_id_seq'::regclass);

--
-- Name: flows id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flows
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.flows_id_seq'::regclass);

--
-- Name: gcs_jobs id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.gcs_jobs
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.gcs_jobs_id_seq'::regclass);

--
-- Name: group_roles id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.group_roles
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.group_roles_id_seq'::regclass);

--
-- Name: groups id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.groups
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.groups_id_seq'::regclass);

--
-- Name: intents id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.intents
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.intents_id_seq'::regclass);

--
-- Name: interactive_templates id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.interactive_templates
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.interactive_templates_id_seq'::regclass);

--
-- Name: invoices id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.invoices
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.invoices_id_seq'::regclass);

--
-- Name: locations id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.locations
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.locations_id_seq'::regclass);

--
-- Name: mail_logs id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.mail_logs
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.mail_logs_id_seq'::regclass);

--
-- Name: message_broadcast_contacts id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.message_broadcast_contacts
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.flow_broadcast_contacts_id_seq'::regclass);

--
-- Name: message_broadcasts id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.message_broadcasts
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.flow_broadcasts_id_seq'::regclass);

--
-- Name: messages id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.messages_id_seq'::regclass);

--
-- Name: messages_conversations id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages_conversations
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.messages_conversations_id_seq'::regclass);

--
-- Name: messages_media id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages_media
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.messages_media_id_seq'::regclass);

--
-- Name: messages_tags id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages_tags
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.messages_tags_id_seq'::regclass);

--
-- Name: notifications id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.notifications
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.notifications_id_seq'::regclass);

--
-- Name: organization_data id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.organization_data
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.organization_data_id_seq'::regclass);

--
-- Name: organizations id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.organizations
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.organizations_id_seq'::regclass);

--
-- Name: profiles id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.profiles
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.profiles_id_seq'::regclass);

--
-- Name: role_permissions id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.role_permissions
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.role_permissions_id_seq'::regclass);

--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.roles
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.roles_id_seq'::regclass);

--
-- Name: saas id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.saas
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.saas_id_seq'::regclass);

--
-- Name: saved_searches id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.saved_searches
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.saved_searches_id_seq'::regclass);

--
-- Name: session_templates id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.session_templates
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.session_templates_id_seq'::regclass);

--
-- Name: sheets id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.sheets
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.sheets_id_seq'::regclass);

--
-- Name: sheets_data id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.sheets_data
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.sheets_data_id_seq'::regclass);

--
-- Name: stats id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.stats
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.stats_id_seq'::regclass);

--
-- Name: tags id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.tags
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.tags_id_seq'::regclass);

--
-- Name: templates_tags id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.templates_tags
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.templates_tags_id_seq'::regclass);

--
-- Name: tickets id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.tickets
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.tickets_id_seq'::regclass);

--
-- Name: trackers id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.trackers
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.trackers_id_seq'::regclass);

--
-- Name: trigger_logs id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.trigger_logs
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.trigger_logs_id_seq'::regclass);

--
-- Name: trigger_roles id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.trigger_roles
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.trigger_roles_id_seq'::regclass);

--
-- Name: triggers id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.triggers
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.triggers_id_seq'::regclass);

--
-- Name: user_roles id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.user_roles
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.user_roles_id_seq'::regclass);

--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.users
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.users_id_seq'::regclass);

--
-- Name: users_groups id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.users_groups
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.users_groups_id_seq'::regclass);

--
-- Name: users_tokens id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.users_tokens
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.users_tokens_id_seq'::regclass);

--
-- Name: webhook_logs id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.webhook_logs
  ALTER COLUMN id SET DEFAULT NEXTVAL('public.webhook_logs_id_seq'::regclass);

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
-- Name: webhook_logs webhook_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.webhook_logs
  ADD CONSTRAINT webhook_logs_pkey PRIMARY KEY (id);

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
-- Name: oban_jobs_meta_index; Type: INDEX; Schema: global; Owner: -
--
CREATE INDEX oban_jobs_meta_index ON global.oban_jobs USING gin (meta);

--
-- Name: oban_jobs_state_queue_priority_scheduled_at_id_index; Type: INDEX; Schema: global; Owner: -
--
CREATE INDEX oban_jobs_state_queue_priority_scheduled_at_id_index ON global.oban_jobs USING btree (state, queue, priority, scheduled_at, id);

--
-- Name: providers_name_index; Type: INDEX; Schema: global; Owner: -
--
CREATE UNIQUE INDEX providers_name_index ON global.providers USING btree (name);

--
-- Name: providers_shortcode_index; Type: INDEX; Schema: global; Owner: -
--
CREATE UNIQUE INDEX providers_shortcode_index ON global.providers USING btree (shortcode);

--
-- Name: billings_organization_id_is_active_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX billings_organization_id_is_active_index ON public.billings USING btree (organization_id, is_active);

--
-- Name: billings_stripe_customer_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX billings_stripe_customer_id_index ON public.billings USING btree (stripe_customer_id);

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
-- Name: contact_histories_contact_id_updated_at_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX contact_histories_contact_id_updated_at_index ON public.contact_histories USING btree (contact_id, updated_at);

--
-- Name: contact_histories_organization_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX contact_histories_organization_id_index ON public.contact_histories USING btree (organization_id);

--
-- Name: contact_histories_updated_at_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX contact_histories_updated_at_index ON public.contact_histories USING btree (updated_at);

--
-- Name: contacts_active_profile_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX contacts_active_profile_id_index ON public.contacts USING btree (active_profile_id)
WHERE (active_profile_id IS NOT NULL);

--
-- Name: contacts_bsp_status_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX contacts_bsp_status_index ON public.contacts USING btree (bsp_status);

--
-- Name: contacts_fields_name_organization_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX contacts_fields_name_organization_id_index ON public.contacts_fields USING btree (name, organization_id);

--
-- Name: contacts_fields_shortcode_organization_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX contacts_fields_shortcode_organization_id_index ON public.contacts_fields USING btree (shortcode, organization_id);

--
-- Name: contacts_groups_contact_id_group_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX contacts_groups_contact_id_group_id_index ON public.contacts_groups USING btree (contact_id, group_id);

--
-- Name: contacts_last_communication_at_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX contacts_last_communication_at_index ON public.contacts USING btree (last_communication_at);

--
-- Name: contacts_last_message_at_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX contacts_last_message_at_index ON public.contacts USING btree (last_message_at)
WHERE (last_message_at IS NOT NULL);

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
CREATE INDEX flow_contexts_completed_at_index ON public.flow_contexts USING btree (completed_at)
WHERE (completed_at IS NOT NULL);

--
-- Name: flow_contexts_contact_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX flow_contexts_contact_id_index ON public.flow_contexts USING btree (contact_id);

--
-- Name: flow_contexts_flow_broadcast_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX flow_contexts_flow_broadcast_id_index ON public.flow_contexts USING btree (message_broadcast_id)
WHERE (message_broadcast_id IS NOT NULL);

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
CREATE INDEX flow_contexts_group_message_id_index ON public.flow_contexts USING btree (group_message_id)
WHERE (group_message_id IS NOT NULL);

--
-- Name: flow_contexts_organization_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX flow_contexts_organization_id_index ON public.flow_contexts USING btree (organization_id);

--
-- Name: flow_contexts_parent_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX flow_contexts_parent_id_index ON public.flow_contexts USING btree (parent_id)
WHERE (parent_id IS NOT NULL);

--
-- Name: flow_contexts_updated_at_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX flow_contexts_updated_at_index ON public.flow_contexts USING btree (updated_at);

--
-- Name: flow_contexts_wakeup_at_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX flow_contexts_wakeup_at_index ON public.flow_contexts USING btree (wakeup_at)
WHERE (wakeup_at IS NOT NULL);

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
CREATE INDEX flow_label_idx_gin ON public.messages USING gin (flow_label public.gin_trgm_ops)
WHERE (flow_label IS NOT NULL);

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
-- Name: gcs_jobs_message_media_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX gcs_jobs_message_media_id_index ON public.gcs_jobs USING btree (message_media_id);

--
-- Name: gcs_jobs_organization_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX gcs_jobs_organization_id_index ON public.gcs_jobs USING btree (organization_id);

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
CREATE INDEX messages_body_idx_gin ON public.messages USING gin (body public.gin_trgm_ops)
WHERE (body IS NOT NULL);

--
-- Name: messages_bsp_message_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX messages_bsp_message_id_organization_id_index ON public.messages USING btree (bsp_message_id, organization_id);

--
-- Name: messages_contact_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX messages_contact_id_index ON public.messages USING btree (contact_id);

--
-- Name: messages_context_message_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX messages_context_message_id_index ON public.messages USING btree (context_message_id)
WHERE (context_message_id IS NOT NULL);

--
-- Name: messages_conversations_organization_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX messages_conversations_organization_id_index ON public.messages_conversations USING btree (organization_id);

--
-- Name: messages_flow_broadcast_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX messages_flow_broadcast_id_index ON public.messages USING btree (message_broadcast_id)
WHERE (message_broadcast_id IS NOT NULL);

--
-- Name: messages_flow_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX messages_flow_id_index ON public.messages USING btree (flow_id);

--
-- Name: messages_group_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX messages_group_id_index ON public.messages USING btree (group_id)
WHERE (group_id IS NOT NULL);

--
-- Name: messages_group_message_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX messages_group_message_id_index ON public.messages USING btree (group_message_id)
WHERE (group_message_id IS NOT NULL);

--
-- Name: messages_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX messages_inserted_at_index ON public.messages USING btree (inserted_at);

--
-- Name: messages_interactive_template_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX messages_interactive_template_id_index ON public.messages USING btree (interactive_template_id)
WHERE (interactive_template_id IS NOT NULL);

--
-- Name: messages_media_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX messages_media_id_index ON public.messages USING btree (media_id)
WHERE (media_id IS NOT NULL);

--
-- Name: messages_media_organization_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX messages_media_organization_id_index ON public.messages_media USING btree (organization_id);

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
CREATE INDEX messages_profile_id_index ON public.messages USING btree (profile_id)
WHERE (profile_id IS NOT NULL);

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
CREATE INDEX messages_template_id_index ON public.messages USING btree (template_id)
WHERE (template_id IS NOT NULL);

--
-- Name: messages_updated_at_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX messages_updated_at_index ON public.messages USING btree (updated_at);

--
-- Name: messages_user_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX messages_user_id_index ON public.messages USING btree (user_id)
WHERE (user_id IS NOT NULL);

--
-- Name: notifications_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX notifications_inserted_at_index ON public.notifications USING btree (inserted_at);

--
-- Name: notifications_organization_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX notifications_organization_id_index ON public.notifications USING btree (organization_id);

--
-- Name: organizations_contact_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX organizations_contact_id_index ON public.organizations USING btree (contact_id);

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
-- Name: webhook_logs_flow_id_index; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX webhook_logs_flow_id_index ON public.webhook_logs USING btree (flow_id);

--
-- Name: oban_jobs oban_notify; Type: TRIGGER; Schema: global; Owner: -
--
CREATE TRIGGER oban_notify
  AFTER INSERT ON global.oban_jobs
  FOR EACH ROW
  EXECUTE FUNCTION global.oban_jobs_notify ();

--
-- Name: tags delete_tag_ancestors_trigger; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER delete_tag_ancestors_trigger
  AFTER DELETE ON public.tags
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.update_tag_ancestors ();

--
-- Name: tags insert_tag_ancestors_trigger; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER insert_tag_ancestors_trigger
  AFTER INSERT ON public.tags
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.update_tag_ancestors ();

--
-- Name: messages message_after_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER message_after_insert_trigger
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.message_after_insert_callback ();

--
-- Name: messages message_before_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER message_before_insert_trigger
  BEFORE INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.message_before_insert_callback ();

--
-- Name: contact_histories remove_old_history_trigger; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER remove_old_history_trigger
  AFTER INSERT ON public.contact_histories
  FOR EACH ROW
  EXECUTE FUNCTION public.remove_old_history ();

--
-- Name: contacts_tags update_contact_updated_at_on_tagging_trigger; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER update_contact_updated_at_on_tagging_trigger
  AFTER INSERT OR DELETE OR UPDATE ON public.contacts_tags
  FOR EACH ROW
  EXECUTE FUNCTION public.update_contact_updated_at_on_tagging ();

--
-- Name: contacts_groups update_contact_updated_at_trigger; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER update_contact_updated_at_trigger
  AFTER INSERT OR DELETE OR UPDATE ON public.contacts_groups
  FOR EACH ROW
  EXECUTE FUNCTION public.update_contact_updated_at ();

--
-- Name: flow_revisions update_flow_revision_number_trigger; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER update_flow_revision_number_trigger
  AFTER INSERT ON public.flow_revisions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_flow_revision_number ();

--
-- Name: messages_tags update_message_updated_at_trigger; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER update_message_updated_at_trigger
  AFTER INSERT OR DELETE OR UPDATE ON public.messages_tags
  FOR EACH ROW
  EXECUTE FUNCTION public.update_message_updated_at ();

--
-- Name: organizations update_organization_id_trigger; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER update_organization_id_trigger
  AFTER INSERT ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION public.update_organization_id ();

--
-- Name: contact_histories update_profile_id_on_new_contact_history; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER update_profile_id_on_new_contact_history
  AFTER INSERT ON public.contact_histories
  FOR EACH ROW
  EXECUTE FUNCTION public.update_profile_id_on_new_contact_history ();

--
-- Name: flow_contexts update_profile_id_on_new_flow_context; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER update_profile_id_on_new_flow_context
  AFTER INSERT ON public.flow_contexts
  FOR EACH ROW
  EXECUTE FUNCTION public.update_profile_id_on_new_flow_context ();

--
-- Name: flow_results update_profile_id_on_new_flow_result; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER update_profile_id_on_new_flow_result
  AFTER INSERT ON public.flow_results
  FOR EACH ROW
  EXECUTE FUNCTION public.update_profile_id_on_new_flow_result ();

--
-- Name: tags update_tag_ancestors_trigger; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER update_tag_ancestors_trigger
  AFTER UPDATE OF parent_id ON public.tags
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.update_tag_ancestors ();

--
-- Name: bigquery_jobs bigquery_jobs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.bigquery_jobs
  ADD CONSTRAINT bigquery_jobs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: billings billings_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.billings
  ADD CONSTRAINT billings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: consulting_hours consulting_hours_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.consulting_hours
  ADD CONSTRAINT consulting_hours_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE SET NULL;

--
-- Name: contact_histories contact_histories_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contact_histories
  ADD CONSTRAINT contact_histories_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: contact_histories contact_histories_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contact_histories
  ADD CONSTRAINT contact_histories_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: contact_histories contact_histories_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contact_histories
  ADD CONSTRAINT contact_histories_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles (id) ON DELETE SET NULL;

--
-- Name: contacts contacts_active_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts
  ADD CONSTRAINT contacts_active_profile_id_fkey FOREIGN KEY (active_profile_id) REFERENCES public.profiles (id) ON DELETE SET NULL;

--
-- Name: contacts_fields contacts_fields_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts_fields
  ADD CONSTRAINT contacts_fields_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: contacts_groups contacts_groups_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts_groups
  ADD CONSTRAINT contacts_groups_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: contacts_groups contacts_groups_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts_groups
  ADD CONSTRAINT contacts_groups_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups (id) ON DELETE CASCADE;

--
-- Name: contacts_groups contacts_groups_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts_groups
  ADD CONSTRAINT contacts_groups_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: contacts contacts_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts
  ADD CONSTRAINT contacts_language_id_fkey FOREIGN KEY (language_id) REFERENCES global.languages (id) ON DELETE RESTRICT;

--
-- Name: contacts contacts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts
  ADD CONSTRAINT contacts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: contacts_tags contacts_tags_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts_tags
  ADD CONSTRAINT contacts_tags_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: contacts_tags contacts_tags_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts_tags
  ADD CONSTRAINT contacts_tags_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: contacts_tags contacts_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.contacts_tags
  ADD CONSTRAINT contacts_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags (id) ON DELETE CASCADE;

--
-- Name: credentials credentials_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.credentials
  ADD CONSTRAINT credentials_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: credentials credentials_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.credentials
  ADD CONSTRAINT credentials_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES global.providers (id);

--
-- Name: extensions extensions_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.extensions
  ADD CONSTRAINT extensions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: message_broadcast_contacts flow_broadcast_contacts_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.message_broadcast_contacts
  ADD CONSTRAINT flow_broadcast_contacts_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: message_broadcast_contacts flow_broadcast_contacts_flow_broadcast_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.message_broadcast_contacts
  ADD CONSTRAINT flow_broadcast_contacts_flow_broadcast_id_fkey FOREIGN KEY (message_broadcast_id) REFERENCES public.message_broadcasts (id) ON DELETE CASCADE;

--
-- Name: message_broadcast_contacts flow_broadcast_contacts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.message_broadcast_contacts
  ADD CONSTRAINT flow_broadcast_contacts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: message_broadcasts flow_broadcasts_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.message_broadcasts
  ADD CONSTRAINT flow_broadcasts_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows (id) ON DELETE CASCADE;

--
-- Name: message_broadcasts flow_broadcasts_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.message_broadcasts
  ADD CONSTRAINT flow_broadcasts_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups (id) ON DELETE CASCADE;

--
-- Name: message_broadcasts flow_broadcasts_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.message_broadcasts
  ADD CONSTRAINT flow_broadcasts_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.messages (id) ON DELETE SET NULL;

--
-- Name: message_broadcasts flow_broadcasts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.message_broadcasts
  ADD CONSTRAINT flow_broadcasts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: message_broadcasts flow_broadcasts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.message_broadcasts
  ADD CONSTRAINT flow_broadcasts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE SET NULL;

--
-- Name: flow_contexts flow_contexts_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_contexts
  ADD CONSTRAINT flow_contexts_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: flow_contexts flow_contexts_flow_broadcast_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_contexts
  ADD CONSTRAINT flow_contexts_flow_broadcast_id_fkey FOREIGN KEY (message_broadcast_id) REFERENCES public.message_broadcasts (id) ON DELETE SET NULL;

--
-- Name: flow_contexts flow_contexts_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_contexts
  ADD CONSTRAINT flow_contexts_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows (id) ON DELETE CASCADE;

--
-- Name: flow_contexts flow_contexts_group_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_contexts
  ADD CONSTRAINT flow_contexts_group_message_id_fkey FOREIGN KEY (group_message_id) REFERENCES public.messages (id) ON DELETE SET NULL;

--
-- Name: flow_contexts flow_contexts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_contexts
  ADD CONSTRAINT flow_contexts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: flow_contexts flow_contexts_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_contexts
  ADD CONSTRAINT flow_contexts_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.flow_contexts (id) ON DELETE SET NULL;

--
-- Name: flow_contexts flow_contexts_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_contexts
  ADD CONSTRAINT flow_contexts_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles (id) ON DELETE SET NULL;

--
-- Name: flow_counts flow_counts_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_counts
  ADD CONSTRAINT flow_counts_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows (id) ON DELETE CASCADE;

--
-- Name: flow_counts flow_counts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_counts
  ADD CONSTRAINT flow_counts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: flow_labels flow_labels_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_labels
  ADD CONSTRAINT flow_labels_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: flow_results flow_results_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_results
  ADD CONSTRAINT flow_results_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: flow_results flow_results_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_results
  ADD CONSTRAINT flow_results_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows (id) ON DELETE CASCADE;

--
-- Name: flow_results flow_results_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_results
  ADD CONSTRAINT flow_results_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: flow_results flow_results_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_results
  ADD CONSTRAINT flow_results_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles (id) ON DELETE SET NULL;

--
-- Name: flow_revisions flow_revisions_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_revisions
  ADD CONSTRAINT flow_revisions_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows (id) ON DELETE CASCADE;

--
-- Name: flow_revisions flow_revisions_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_revisions
  ADD CONSTRAINT flow_revisions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: flow_revisions flow_revisions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_revisions
  ADD CONSTRAINT flow_revisions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE SET NULL;

--
-- Name: flow_roles flow_roles_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_roles
  ADD CONSTRAINT flow_roles_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows (id) ON DELETE CASCADE;

--
-- Name: flow_roles flow_roles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_roles
  ADD CONSTRAINT flow_roles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: flow_roles flow_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flow_roles
  ADD CONSTRAINT flow_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles (id) ON DELETE CASCADE;

--
-- Name: flows flows_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flows
  ADD CONSTRAINT flows_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: flows flows_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.flows
  ADD CONSTRAINT flows_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags (id);

--
-- Name: gcs_jobs gcs_jobs_message_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.gcs_jobs
  ADD CONSTRAINT gcs_jobs_message_media_id_fkey FOREIGN KEY (message_media_id) REFERENCES public.messages_media (id) ON DELETE SET NULL;

--
-- Name: gcs_jobs gcs_jobs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.gcs_jobs
  ADD CONSTRAINT gcs_jobs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: group_roles group_roles_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.group_roles
  ADD CONSTRAINT group_roles_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups (id) ON DELETE CASCADE;

--
-- Name: group_roles group_roles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.group_roles
  ADD CONSTRAINT group_roles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: group_roles group_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.group_roles
  ADD CONSTRAINT group_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles (id) ON DELETE CASCADE;

--
-- Name: groups groups_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.groups
  ADD CONSTRAINT groups_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: intents intents_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.intents
  ADD CONSTRAINT intents_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: interactive_templates interactive_templates_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.interactive_templates
  ADD CONSTRAINT interactive_templates_language_id_fkey FOREIGN KEY (language_id) REFERENCES global.languages (id) ON DELETE RESTRICT;

--
-- Name: interactive_templates interactive_templates_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.interactive_templates
  ADD CONSTRAINT interactive_templates_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: interactive_templates interactive_templates_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.interactive_templates
  ADD CONSTRAINT interactive_templates_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags (id);

--
-- Name: invoices invoices_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.invoices
  ADD CONSTRAINT invoices_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: locations locations_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.locations
  ADD CONSTRAINT locations_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: locations locations_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.locations
  ADD CONSTRAINT locations_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.messages (id) ON DELETE CASCADE;

--
-- Name: locations locations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.locations
  ADD CONSTRAINT locations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: mail_logs mail_logs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.mail_logs
  ADD CONSTRAINT mail_logs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: message_broadcasts message_broadcasts_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.message_broadcasts
  ADD CONSTRAINT message_broadcasts_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows (id) ON DELETE CASCADE;

--
-- Name: messages messages_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: messages messages_context_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_context_message_id_fkey FOREIGN KEY (context_message_id) REFERENCES public.messages (id) ON DELETE CASCADE;

--
-- Name: messages_conversations messages_conversations_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages_conversations
  ADD CONSTRAINT messages_conversations_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.messages (id) ON DELETE CASCADE;

--
-- Name: messages_conversations messages_conversations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages_conversations
  ADD CONSTRAINT messages_conversations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: messages messages_flow_broadcast_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_flow_broadcast_id_fkey FOREIGN KEY (message_broadcast_id) REFERENCES public.message_broadcasts (id) ON DELETE SET NULL;

--
-- Name: messages messages_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows (id) ON DELETE SET NULL;

--
-- Name: messages messages_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups (id) ON DELETE CASCADE;

--
-- Name: messages messages_group_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_group_message_id_fkey FOREIGN KEY (group_message_id) REFERENCES public.messages (id) ON DELETE SET NULL;

--
-- Name: messages messages_interactive_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_interactive_template_id_fkey FOREIGN KEY (interactive_template_id) REFERENCES public.interactive_templates (id) ON DELETE SET NULL;

--
-- Name: messages messages_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.messages_media (id) ON DELETE CASCADE;

--
-- Name: messages_media messages_media_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages_media
  ADD CONSTRAINT messages_media_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: messages messages_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: messages messages_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles (id) ON DELETE SET NULL;

--
-- Name: messages messages_receiver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_receiver_id_fkey FOREIGN KEY (receiver_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: messages messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: messages_tags messages_tags_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages_tags
  ADD CONSTRAINT messages_tags_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.messages (id) ON DELETE CASCADE;

--
-- Name: messages_tags messages_tags_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages_tags
  ADD CONSTRAINT messages_tags_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: messages_tags messages_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages_tags
  ADD CONSTRAINT messages_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags (id) ON DELETE CASCADE;

--
-- Name: messages messages_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.session_templates (id) ON DELETE SET NULL;

--
-- Name: messages messages_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.messages
  ADD CONSTRAINT messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE SET NULL;

--
-- Name: notifications notifications_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.notifications
  ADD CONSTRAINT notifications_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: organization_data organization_data_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.organization_data
  ADD CONSTRAINT organization_data_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: organizations organizations_default_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.organizations
  ADD CONSTRAINT organizations_default_language_id_fkey FOREIGN KEY (default_language_id) REFERENCES global.languages (id) ON DELETE RESTRICT;

--
-- Name: organizations organizations_newcontact_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.organizations
  ADD CONSTRAINT organizations_newcontact_flow_id_fkey FOREIGN KEY (newcontact_flow_id) REFERENCES public.flows (id) ON DELETE SET NULL;

--
-- Name: organizations organizations_optin_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.organizations
  ADD CONSTRAINT organizations_optin_flow_id_fkey FOREIGN KEY (optin_flow_id) REFERENCES public.flows (id) ON DELETE SET NULL;

--
-- Name: organizations organizations_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.organizations
  ADD CONSTRAINT organizations_provider_id_fkey FOREIGN KEY (bsp_id) REFERENCES global.providers (id);

--
-- Name: profiles profiles_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.profiles
  ADD CONSTRAINT profiles_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: profiles profiles_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.profiles
  ADD CONSTRAINT profiles_language_id_fkey FOREIGN KEY (language_id) REFERENCES global.languages (id) ON DELETE CASCADE;

--
-- Name: profiles profiles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.profiles
  ADD CONSTRAINT profiles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: role_permissions role_permissions_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.role_permissions
  ADD CONSTRAINT role_permissions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: role_permissions role_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.role_permissions
  ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES global.permissions (id) ON DELETE CASCADE;

--
-- Name: role_permissions role_permissions_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.role_permissions
  ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles (id) ON DELETE CASCADE;

--
-- Name: roles roles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.roles
  ADD CONSTRAINT roles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: saas saas_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.saas
  ADD CONSTRAINT saas_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: saved_searches saved_searches_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.saved_searches
  ADD CONSTRAINT saved_searches_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: session_templates session_templates_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.session_templates
  ADD CONSTRAINT session_templates_language_id_fkey FOREIGN KEY (language_id) REFERENCES global.languages (id) ON DELETE RESTRICT;

--
-- Name: session_templates session_templates_message_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.session_templates
  ADD CONSTRAINT session_templates_message_media_id_fkey FOREIGN KEY (message_media_id) REFERENCES public.messages_media (id) ON DELETE CASCADE;

--
-- Name: session_templates session_templates_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.session_templates
  ADD CONSTRAINT session_templates_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: session_templates session_templates_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.session_templates
  ADD CONSTRAINT session_templates_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.session_templates (id) ON DELETE SET NULL;

--
-- Name: session_templates session_templates_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.session_templates
  ADD CONSTRAINT session_templates_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags (id);

--
-- Name: sheets_data sheets_data_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.sheets_data
  ADD CONSTRAINT sheets_data_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: sheets_data sheets_data_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.sheets_data
  ADD CONSTRAINT sheets_data_sheet_id_fkey FOREIGN KEY (sheet_id) REFERENCES public.sheets (id) ON DELETE CASCADE;

--
-- Name: sheets sheets_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.sheets
  ADD CONSTRAINT sheets_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: stats stats_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.stats
  ADD CONSTRAINT stats_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: tags tags_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.tags
  ADD CONSTRAINT tags_language_id_fkey FOREIGN KEY (language_id) REFERENCES global.languages (id) ON DELETE RESTRICT;

--
-- Name: tags tags_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.tags
  ADD CONSTRAINT tags_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: tags tags_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.tags
  ADD CONSTRAINT tags_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.tags (id) ON DELETE SET NULL;

--
-- Name: templates_tags templates_tags_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.templates_tags
  ADD CONSTRAINT templates_tags_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: templates_tags templates_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.templates_tags
  ADD CONSTRAINT templates_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags (id) ON DELETE CASCADE;

--
-- Name: templates_tags templates_tags_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.templates_tags
  ADD CONSTRAINT templates_tags_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.session_templates (id) ON DELETE CASCADE;

--
-- Name: tickets tickets_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.tickets
  ADD CONSTRAINT tickets_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: tickets tickets_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.tickets
  ADD CONSTRAINT tickets_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: tickets tickets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.tickets
  ADD CONSTRAINT tickets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE SET NULL;

--
-- Name: trackers trackers_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.trackers
  ADD CONSTRAINT trackers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: trigger_logs trigger_logs_flow_context_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.trigger_logs
  ADD CONSTRAINT trigger_logs_flow_context_id_fkey FOREIGN KEY (flow_context_id) REFERENCES public.flow_contexts (id) ON DELETE CASCADE;

--
-- Name: trigger_logs trigger_logs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.trigger_logs
  ADD CONSTRAINT trigger_logs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: trigger_logs trigger_logs_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.trigger_logs
  ADD CONSTRAINT trigger_logs_trigger_id_fkey FOREIGN KEY (trigger_id) REFERENCES public.triggers (id) ON DELETE CASCADE;

--
-- Name: trigger_roles trigger_roles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.trigger_roles
  ADD CONSTRAINT trigger_roles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: trigger_roles trigger_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.trigger_roles
  ADD CONSTRAINT trigger_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles (id) ON DELETE CASCADE;

--
-- Name: trigger_roles trigger_roles_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.trigger_roles
  ADD CONSTRAINT trigger_roles_trigger_id_fkey FOREIGN KEY (trigger_id) REFERENCES public.triggers (id) ON DELETE CASCADE;

--
-- Name: triggers triggers_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.triggers
  ADD CONSTRAINT triggers_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows (id) ON DELETE CASCADE;

--
-- Name: triggers triggers_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.triggers
  ADD CONSTRAINT triggers_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups (id) ON DELETE CASCADE;

--
-- Name: triggers triggers_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.triggers
  ADD CONSTRAINT triggers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: user_roles user_roles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.user_roles
  ADD CONSTRAINT user_roles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: user_roles user_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.user_roles
  ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles (id) ON DELETE CASCADE;

--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.user_roles
  ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE;

--
-- Name: users users_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.users
  ADD CONSTRAINT users_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: users_groups users_groups_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.users_groups
  ADD CONSTRAINT users_groups_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.groups (id) ON DELETE CASCADE;

--
-- Name: users_groups users_groups_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.users_groups
  ADD CONSTRAINT users_groups_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: users_groups users_groups_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.users_groups
  ADD CONSTRAINT users_groups_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE;

--
-- Name: users users_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.users
  ADD CONSTRAINT users_language_id_fkey FOREIGN KEY (language_id) REFERENCES global.languages (id) ON DELETE RESTRICT;

--
-- Name: users users_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.users
  ADD CONSTRAINT users_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: users_tokens users_tokens_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.users_tokens
  ADD CONSTRAINT users_tokens_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- Name: users_tokens users_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.users_tokens
  ADD CONSTRAINT users_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE;

--
-- Name: webhook_logs webhook_logs_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.webhook_logs
  ADD CONSTRAINT webhook_logs_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts (id) ON DELETE CASCADE;

--
-- Name: webhook_logs webhook_logs_flow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.webhook_logs
  ADD CONSTRAINT webhook_logs_flow_id_fkey FOREIGN KEY (flow_id) REFERENCES public.flows (id) ON DELETE CASCADE;

--
-- Name: webhook_logs webhook_logs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.webhook_logs
  ADD CONSTRAINT webhook_logs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE CASCADE;

--
-- PostgreSQL database dump complete
--
INSERT INTO public."schema_migrations" (version)
  VALUES (20200101010533);

INSERT INTO public."schema_migrations" (version)
  VALUES (20200601193405);

INSERT INTO public."schema_migrations" (version)
  VALUES (20200615073630);

INSERT INTO public."schema_migrations" (version)
  VALUES (20200710170410);

INSERT INTO public."schema_migrations" (version)
  VALUES (20200727180623);

INSERT INTO public."schema_migrations" (version)
  VALUES (20200826081727);

INSERT INTO public."schema_migrations" (version)
  VALUES (20200924193405);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201006113225);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201013101431);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201023101018);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201027171943);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201028073000);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201101121212);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201109045808);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201109104646);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201111013043);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201111063858);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201113072446);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201127092412);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201201143144);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201207123324);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201214124257);

INSERT INTO public."schema_migrations" (version)
  VALUES (20201222120543);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210106110739);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210114100139);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210119132444);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210121071908);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210125052414);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210125060448);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210130040741);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210201172459);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210203172842);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210210023539);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210218003423);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210218084225);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210220013242);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210225083751);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210308092147);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210316195915);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210321001630);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210322182605);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210324073555);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210325044923);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210326234327);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210406052407);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210409045013);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210417014050);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210417183726);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210417224300);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210418014629);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210423062238);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210501222848);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210511080620);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210517055305);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210521112227);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210526083141);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210527125035);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210610093045);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210616074312);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210630101412);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210707060535);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210722094027);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210806092436);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210817103124);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210915070956);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210920042723);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210921164609);

INSERT INTO public."schema_migrations" (version)
  VALUES (20210930102613);

INSERT INTO public."schema_migrations" (version)
  VALUES (20211026123120);

INSERT INTO public."schema_migrations" (version)
  VALUES (20211124063048);

INSERT INTO public."schema_migrations" (version)
  VALUES (20211129114942);

INSERT INTO public."schema_migrations" (version)
  VALUES (20211129193305);

INSERT INTO public."schema_migrations" (version)
  VALUES (20211130120043);

INSERT INTO public."schema_migrations" (version)
  VALUES (20211222095004);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220103194517);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220105070545);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220107123528);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220111122456);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220125085553);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220129095329);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220211220835);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220216151507);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220217210850);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220228100913);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220314060653);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220328113810);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220331123334);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220421053535);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220509103325);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220606122101);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220609073705);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220614095610);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220615045615);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220616055250);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220725085345);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220804173617);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220823091156);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220826061242);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220905054418);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220906140729);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220915095949);

INSERT INTO public."schema_migrations" (version)
  VALUES (20220929062917);

INSERT INTO public."schema_migrations" (version)
  VALUES (20221011082819);

INSERT INTO public."schema_migrations" (version)
  VALUES (20221012062208);

INSERT INTO public."schema_migrations" (version)
  VALUES (20221013081740);

INSERT INTO public."schema_migrations" (version)
  VALUES (20221108092656);

INSERT INTO public."schema_migrations" (version)
  VALUES (20221125132509);

INSERT INTO public."schema_migrations" (version)
  VALUES (20221130112021);

INSERT INTO public."schema_migrations" (version)
  VALUES (20221202103552);

INSERT INTO public."schema_migrations" (version)
  VALUES (20221223030323);

INSERT INTO public."schema_migrations" (version)
  VALUES (20230104054512);

INSERT INTO public."schema_migrations" (version)
  VALUES (20230131111743);

INSERT INTO public."schema_migrations" (version)
  VALUES (20230202072241);

INSERT INTO public."schema_migrations" (version)
  VALUES (20230314073042);

INSERT INTO public."schema_migrations" (version)
  VALUES (20230316080512);

INSERT INTO public."schema_migrations" (version)
  VALUES (20230403001516);

INSERT INTO public."schema_migrations" (version)
  VALUES (20230408024016);

INSERT INTO public."schema_migrations" (version)
  VALUES (20230502060609);

INSERT INTO public."schema_migrations" (version)
  VALUES (20230507220819);

INSERT INTO public."schema_migrations" (version)
  VALUES (20230512175955);

INSERT INTO public."schema_migrations" (version)
  VALUES (20230522105210);

INSERT INTO public."schema_migrations" (version)
  VALUES (20230616045651);

INSERT INTO public."schema_migrations" (version)
  VALUES (20230627145331);

