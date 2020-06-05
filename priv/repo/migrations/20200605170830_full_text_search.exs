defmodule Glific.Repo.Migrations.FullTextSearch do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    execute("CREATE EXTENSION IF NOT EXISTS unaccent")

    execute(
      """
      CREATE MATERIALIZED VIEW message_search AS
      SELECT
      contact.id  AS contact_id,
      messages.id AS messages_id,
      contact.name AS contact_name,
      (
      setweight(to_tsvector(unaccent(contact.name || ' ' || contact.phone)), 'A') ||
      setweight(to_tsvector(unaccent(coalesce(string_agg(tags.label, ' '), ' '))), 'B')
      setweight(to_tsvector(unaccent(message.body || ' ' || message_media.caption)), 'C')
      ) AS document
      FROM contacts
      LEFT JOIN messages ON (messages.sender_id == contact.id OR messages.receiver_id == contact.id)
      LEFT JOIN message_media ON messages.media_id == message_media.id
      LEFT JOIN messages_tags ON  messages.id == messages_tags.message_id
      LEFT JOIN tags ON tags.id == messages_tags.tag_id
      GROUP BY contact.id
      """
    )

    # to support full-text searches
    create index("message_search", ["document"], using: :gin)

    # to support substring title matches with ILIKE
    execute("CREATE INDEX recipe_search_title_trgm_index ON recipe_search USING gin (title gin_trgm_ops)")

    # to support updating CONCURRENTLY
    create unique_index("recipe_search", [:id])
  end

  def down do
    execute("DROP EXTENSION IF EXISTS pg_trgm")
    execute("DROP EXTENSION IF EXISTS unaccent")
  end
end
