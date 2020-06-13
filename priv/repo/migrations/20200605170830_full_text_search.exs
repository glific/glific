defmodule Glific.Repo.Migrations.FullTextSearch do
  use Ecto.Migration

  def up do
    create_extensions()

    create_view()

    search_messages()

    create_functions()

    create_triggers()
  end

  defp create_extensions do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    execute("CREATE EXTENSION IF NOT EXISTS unaccent")
  end

  defp create_view do
    execute("""
    DROP VIEW IF EXISTS partitioned_messages;
    CREATE VIEW partitioned_messages AS (
    SELECT *,
    row_number() OVER (PARTITION BY contact_id ORDER BY updated_at DESC) AS rank
    FROM messages
    );
    """)
  end

  defp create_functions do
    execute("""
DROP FUNCTION IF EXISTS create_search_messages;
CREATE OR REPLACE FUNCTION create_search_messages(N numeric) RETURNS TEXT AS
$$
BEGIN
    EXECUTE ('DELETE FROM search_messages');
    INSERT INTO search_messages(contact_id, name, phone, tag_label, document)
    SELECT contacts.id,
           contacts.name,
           contacts.phone,
           coalesce(string_agg(tags.label, ' '), ''),
           (
              setweight(to_tsvector(unaccent(contacts.name || ' ' || contacts.phone)), 'A') ||
              setweight(to_tsvector(unaccent(
                 coalesce(string_agg(tags.label, ' ' order by messages.inserted_at), ' '))), 'B') ||
              setweight(to_tsvector(unaccent(coalesce(
                 string_agg(messages.body, ' ' order by messages.inserted_at), ' '))), 'C')
           )
    FROM contacts
    LEFT JOIN partitioned_messages messages
           ON (messages.sender_id = contacts.id OR messages.receiver_id = contacts.id)
    LEFT JOIN messages_tags ON messages.id = messages_tags.message_id
    LEFT JOIN tags ON tags.id = messages_tags.tag_id
    WHERE messages.rank <= N
    GROUP BY contacts.id;
    RETURN 'search_messages updated with last ' || N || ' messages';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
    """)

    execute("""
    DROP FUNCTION IF EXISTS update_contact;
    CREATE OR REPLACE FUNCTION update_contact(
      contact_id numeric,
      label text,
      message text)
    RETURNS BOOLEAN AS
    $$
    BEGIN
    UPDATE search_messages
    SET
      tag_label = tag_label || ' ' || coalesce(update_contact.label, ''),
      document  = (document || (setweight(to_tsvector(unaccent(coalesce(label, ' '))), 'B') ||
      setweight(to_tsvector(unaccent(coalesce(message, ' '))), 'C')))::tsvector
    WHERE contact_id = update_contact.contact_id;
    RETURN FOUND;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;
    """)
  end

  @doc """
  Create a table for full text search. This eliminates the need to do anything
  dynamically and we can return really quickly
  """
  def search_messages do
    create table(:search_messages) do
      add :name, :string
      add :phone, :string
      add :tag_label, :text
      add :document, :tsvector

      add :contact_id, references(:contacts, on_delete: :delete_all)

      timestamps()
    end

    execute("""
    CREATE INDEX search_messages_index ON search_messages using gin(to_tsvector('english', document))
    """)

    create index(:search_messages, :name)
    create index(:search_messages, :phone)
    create index(:search_messages, :tag_label)
  end

  defp create_triggers do
    execute("""
    CREATE TRIGGER message_search_update
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON contacts
    FOR EACH STATEMENT
    EXECUTE PROCEDURE message_search_update();
    """)

    execute("""
    CREATE TRIGGER message_search_update
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON messages
    FOR EACH STATEMENT
    EXECUTE PROCEDURE message_search_update();
    """)

    execute("""
    CREATE TRIGGER message_search_update
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON tags
    FOR EACH STATEMENT
    EXECUTE PROCEDURE message_search_update();
    """)

    execute("""
    CREATE TRIGGER message_search_update
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON messages_tags
    FOR EACH STATEMENT
    EXECUTE PROCEDURE message_search_update();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS message_search_update ON contacts")
    execute("DROP TRIGGER IF EXISTS message_search_update ON messages")
    execute("DROP TRIGGER IF EXISTS message_search_update ON tags")
    execute("DROP TRIGGER IF EXISTS message_search_update ON messages_tags")

    execute("DROP VIEW IF EXISTS partitioned_message")

    execute("DROP FUNCTION IF EXISTS create_search_messages")
    execute("DROP FUNCTION IF EXISTS update_contact")

    execute("DROP EXTENSION IF EXISTS pg_trgm")
    execute("DROP EXTENSION IF EXISTS unaccent")
  end
end
