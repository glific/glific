defmodule Glific.Repo.Migrations.FullTextSearch do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    execute("CREATE EXTENSION IF NOT EXISTS unaccent")

    execute(
      """
      CREATE MATERIALIZED VIEW message_search AS
      SELECT
      contacts.id  AS id,
      contacts.name || ' ' || contacts.phone AS name,
      (
      setweight(to_tsvector(unaccent(contacts.name || ' ' || contacts.phone)), 'A') ||
      setweight(to_tsvector(unaccent(coalesce(string_agg(tags.label, ' '), ' '))), 'B') ||
      setweight(to_tsvector(unaccent(coalesce(string_agg(messages.body, ' '), ' '))), 'C') ||
      setweight(to_tsvector(unaccent(coalesce(string_agg(message_media.caption, ' '), ' '))), 'D')
      ) AS document
      FROM  contacts
      LEFT  JOIN messages ON (messages.sender_id = contacts.id OR messages.recipient_id = contacts.id)
      LEFT  JOIN message_media ON messages.media_id = message_media.id
      LEFT  JOIN messages_tags ON  messages.id = messages_tags.message_id
      LEFT  JOIN tags ON tags.id = messages_tags.tag_id
      GROUP BY contacts.id
      """
    )

    # to support full-text searches
    create index("message_search", ["document"], using: :gin)

    # to support substring title matches with ILIKE
    execute("CREATE INDEX message_search_name_index ON message_search USING gin (name gin_trgm_ops)")

    # to support updating CONCURRENTLY
    create unique_index("message_search", [:id])
  end

  def down do
    execute("DROP EXTENSION IF EXISTS pg_trgm")
    execute("DROP EXTENSION IF EXISTS unaccent")

    execute("DROP INDEX message_search_document")
    execute("DROP INDEX message_search_name_index")
    execute("DROP INDEX message_search_id")

    execute("DROP MATERIALIZED VIEW message_search")
  end
end
