defmodule Glific.Repo.Migrations.FullTextSearch do
  use Ecto.Migration

  def up do
    create_extensions()

    create_table()

    create_view()

    create_functions()

    create_triggers()
  end

  def down do
    drop_extensions()

    drop_table()

    drop_view()

    drop_functions()

    drop_triggers()
  end

  defp create_extensions do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    execute("CREATE EXTENSION IF NOT EXISTS unaccent")
  end

  defp drop_extensions do
    execute("DROP EXTENSION IF EXISTS pg_trgm")
    execute("DROP EXTENSION IF EXISTS unaccent")
  end

  # Create a table for full text search. This eliminates the need to do anything
  # dynamically and we can return really quickly
  defp create_table do
    create table(:search_messages) do
      add :name, :string
      add :phone, :string
      add :tag_label, {:array, :string}
      add :document, :tsvector

      add :contact_id, references(:contacts, on_delete: :delete_all)
    end

    execute("CREATE INDEX search_messages_index ON search_messages using gin(document)")
    create index(:search_messages, :name)
    create index(:search_messages, :phone)
    create index(:search_messages, :tag_label)
  end

  defp drop_table do
    execute("DROP TABLE IF EXISTS search_messages")
  end

  defp create_view() do
    drop_view()

    # this view partitions messages which can be used to pick last n messages per contact id
    execute("""
    CREATE VIEW partitioned_messages AS (
      SELECT *,
        row_number() OVER (PARTITION BY contact_id ORDER BY updated_at DESC) AS rank
      FROM messages
    );
    """)
  end

  defp drop_view do
    execute("""
    DROP VIEW IF EXISTS partitioned_messages;
    """)
  end

  defp create_functions do
    # lets drop all functions to be on the safe side
    drop_functions()

    # function to populate values into search_messages
    execute("""
    CREATE OR REPLACE FUNCTION create_search_messages(N numeric) RETURNS TEXT AS
    $$
    BEGIN
      EXECUTE ('DELETE FROM search_messages');
      INSERT INTO search_messages(contact_id, name, phone, tag_label, document)
        SELECT contacts.id,
          contacts.name,
          contacts.phone,
          array_remove(array_agg(distinct tags.label), null),
          (setweight(to_tsvector(unaccent(contacts.name || ' ' || contacts.phone)), 'A') ||
           setweight(to_tsvector(unaccent(
             coalesce(string_agg(tags.label, ' ' order by tags.inserted_at), ' '))), 'B') ||
           setweight(to_tsvector(unaccent(coalesce(
             string_agg(messages.body, ' ' order by messages.inserted_at), ' '))), 'C'))
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

    # trigger function for messages
    execute("""
    CREATE OR REPLACE FUNCTION update_search_messages_on_messages_update()
      RETURNS TRIGGER AS
    $$
    BEGIN
      IF (tg_op = 'INSERT') THEN
        IF ((SELECT count(*) FROM search_messages WHERE contact_id = new.contact_id) = 0) THEN
          RAISE INFO 'inserting new record %', new.contact_id;
          INSERT INTO search_messages(contact_id, name, phone, tag_label, document)
            SELECT contacts.id,
              contacts.name,
              contacts.phone,
              array_remove(ARRAY [tags.label], null),
              (setweight(to_tsvector(unaccent(contacts.name || ' ' || contacts.phone)), 'A') ||
               setweight(to_tsvector(unaccent(coalesce(tags.label, ' '))), 'B') ||
               setweight(to_tsvector(unaccent(coalesce(messages.body, ' '))), 'C'))
            FROM messages
            LEFT JOIN contacts on messages.contact_id = contacts.id
            LEFT JOIN messages_tags ON messages.id = messages_tags.message_id
            LEFT JOIN tags ON tags.id = messages_tags.tag_id
            WHERE messages.contact_id = new.contact_id;
        ELSE
          RAISE INFO 'updating existing record %', new.contact_id;
          UPDATE search_messages
            SET document = (document || (setweight(to_tsvector(unaccent(coalesce(new.body, ' '))), 'C')))::tsvector;
        END IF;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    # trigger function for contacts
    execute("""
    CREATE OR REPLACE FUNCTION update_search_messages_on_contacts_update()
    RETURNS TRIGGER AS
    $$
    BEGIN
      IF (tg_op = 'DELETE') THEN
        RAISE INFO 'deleting contact id % from search_messages', old.id;
        DELETE FROM search_messages WHERE contact_id = old.id;
      END IF;
      RETURN new;
    END ;
    $$ LANGUAGE plpgsql;
    """)

    # trigger function for messages_tags
    execute("""
    CREATE OR REPLACE FUNCTION update_search_messages_on_messages_tags_update()
      RETURNS TRIGGER AS
      $$
      BEGIN
        IF (tg_op = 'INSERT') THEN
          RAISE INFO 'updating search messages to add message tag id %', new.tag_id;
          WITH new_data AS (
            SELECT tags.label          AS label,
                   messages.contact_id AS contact_id
            FROM messages_tags
            JOIN messages on messages_tags.message_id = messages.id
            JOIN tags ON tags.id = messages_tags.tag_id
            WHERE messages_tags.id = new.id
          )
          UPDATE search_messages
            SET
              tag_label = CASE
                WHEN label = ANY (tag_label) then tag_label
                WHEN label is null then tag_label
                ELSE array_prepend(label::character varying, tag_label)
              END,
              document  = (document || (setweight(to_tsvector(unaccent(coalesce(label, ' '))), 'B')))::tsvector
            FROM new_data
            WHERE search_messages.contact_id = new_data.contact_id;
        END IF;
        RETURN NEW;
      END ;
      $$ LANGUAGE plpgsql;
    """)
  end

  defp drop_functions do
    execute("""
    DROP FUNCTION IF EXISTS create_search_messages;
    """)

    execute("""
    DROP FUNCTION IF EXISTS update_search_messages_on_messages_update();
    """)

    execute("""
    DROP FUNCTION IF EXISTS update_search_messages_on_contacts_update();
    """)

    execute("""
    DROP FUNCTION IF EXISTS update_search_messages_on_messages_tags_update();
    """)
  end

  defp create_triggers do
    drop_triggers()

    # insert trigger on messages
    execute("""
    CREATE TRIGGER update_search_message_trigger
    AFTER INSERT
    ON messages
      FOR EACH ROW
        EXECUTE PROCEDURE update_search_messages_on_messages_update();
    """)

    # trigger for contact delete
    execute("""
    CREATE TRIGGER update_search_message_trigger
    AFTER DELETE
    ON contacts
      FOR EACH ROW
        EXECUTE PROCEDURE update_search_messages_on_contacts_update();
    """)

    # trigger for messages_tags insert
    execute("""
    CREATE TRIGGER update_search_message_trigger
    AFTER INSERT
    ON messages_tags
      FOR EACH ROW
        EXECUTE PROCEDURE update_search_messages_on_messages_tags_update();
    """)
  end

  defp drop_triggers do
    execute("""
    DROP TRIGGER IF EXISTS update_search_message_trigger ON messages
    """)

    execute("""
    DROP TRIGGER IF EXISTS update_search_message_trigger ON contacts
    """)

    execute("""
    DROP TRIGGER IF EXISTS update_search_message_trigger ON messages_tags
    """)
  end
end
