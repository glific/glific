defmodule Glific.Repo.Migrations.AddGetConversationFunction do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION public.conversation_message_ids(ids bigint[], contact_limit integer, contact_offset integer, message_limit integer, message_offset integer)
    RETURNS bigint[]
    LANGUAGE plpgsql
    AS $function$

    DECLARE message_ids BIGINT[];
    DECLARE contact_ids BIGINT[];

    BEGIN
      contact_ids := ids;

      IF CARDINALITY(ids) < 1 THEN
          contact_ids := Array(SELECT contact_id FROM messages where message_number = 0 ORDER BY updated_at DESC OFFSET contact_offset LIMIT contact_limit);
      END IF;

      message_ids := Array(SELECT id FROM messages where contact_id = ANY(contact_ids) and message_number >= message_offset and message_number < message_offset + message_limit ORDER by message_number);

      RETURN message_ids;
    END;

    $function$
    """
  end

  def down do
    execute "DROP FUNCTION conversation_message_ids(contact_limit integer, contact_offset integer, message_limit integer, message_offset integer) CASCADE;"
  end
end
