defmodule Glific.Repo.Migrations.FullTextSearch do
  use Ecto.Migration

  def up do
    create_extensions()

    create_view()

    create_indexes()

    create_triggers()
  end

  defp create_extensions do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    execute("CREATE EXTENSION IF NOT EXISTS unaccent")
  end

  defp create_view do
    execute("""
    CREATE MATERIALIZED VIEW message_search AS
    SELECT
    contacts.id  AS id,
    contacts.name || ' ' || contacts.phone AS contact_label,
    coalesce(string_agg(tags.label, ' '), ' ') AS tag_label,
    (
    setweight(to_tsvector(unaccent(contacts.name || ' ' || contacts.phone)), 'A') ||
    setweight(to_tsvector(unaccent(coalesce(string_agg(tags.label, ' '), ' '))), 'B') ||
    setweight(to_tsvector(unaccent(coalesce(string_agg(messages.body, ' '), ' '))), 'C')
    ) AS document
    FROM  contacts
    LEFT  JOIN messages ON (messages.sender_id = contacts.id OR messages.receiver_id = contacts.id)
    LEFT  JOIN messages_tags ON  messages.id = messages_tags.message_id
    LEFT  JOIN tags ON tags.id = messages_tags.tag_id
    GROUP BY contacts.id
    """)
  end

  defp create_indexes do
    # to support full-text searches
    create index("message_search", ["document"], using: :gin)

    # to support substring title matches with ILIKE
    execute(
      "CREATE INDEX message_search_contact_index ON message_search USING gin (contact_label gin_trgm_ops)"
    )

    execute(
      "CREATE INDEX message_search_tag_index ON message_search USING gin (tag_label gin_trgm_ops)"
    )

    # to support updating CONCURRENTLY
    create unique_index("message_search", [:id])
  end

  defp create_triggers do
    execute("""
    CREATE OR REPLACE FUNCTION refresh_message_search()
    RETURNS TRIGGER LANGUAGE plpgsql
    AS $$
    BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY message_search;
    RETURN NULL;
    END $$;
    """)

    execute("""
    CREATE TRIGGER refresh_message_search
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON contacts
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_message_search();
    """)

    execute("""
    CREATE TRIGGER refresh_message_search
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON messages
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_message_search();
    """)

    execute("""
    CREATE TRIGGER refresh_message_search
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON tags
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_message_search();
    """)

    execute("""
    CREATE TRIGGER refresh_message_search
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON messages_tags
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_message_search();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS refresh_message_search ON contacts")
    execute("DROP TRIGGER IF EXISTS refresh_message_search ON messages")
    execute("DROP TRIGGER IF EXISTS refresh_message_search ON tags")
    execute("DROP TRIGGER IF EXISTS refresh_message_search ON messages_tags")

    execute("DROP INDEX IF EXISTS message_search_document_index")
    execute("DROP INDEX IF EXISTS message_search_contact_index")
    execute("DROP INDEX IF EXISTS message_search_tag_index")
    execute("DROP INDEX IF EXISTS message_search_id_index")

    execute("DROP MATERIALIZED VIEW IF EXISTS message_search")

    execute("DROP EXTENSION IF EXISTS pg_trgm")
    execute("DROP EXTENSION IF EXISTS unaccent")
  end
end
