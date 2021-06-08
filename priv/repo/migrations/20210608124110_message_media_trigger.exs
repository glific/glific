defmodule Glific.Repo.Migrations.MessageMediaTrigger do
  use Ecto.Migration

  def up do
    message_media_trigger()
  end

  defp message_media_trigger do
    execute """
    CREATE OR REPLACE FUNCTION update_message_updated_at()
      RETURNS trigger AS $$

      BEGIN
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
        IF (TG_OP = 'UPDATE') THEN

          UPDATE messages set updated_at = (CURRENT_TIMESTAMP at time zone 'utc') where media_id = NEW.id;
        ELSE
          IF (TG_OP = 'DELETE') THEN
            UPDATE messages set updated_at = (CURRENT_TIMESTAMP at time zone 'utc') where media_id = old.id;

          END IF;
        END IF;
        RETURN NULL;
      END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER update_message_updated_at_trigger
    AFTER UPDATE
    ON messages_media
    FOR EACH ROW
    EXECUTE PROCEDURE update_message_updated_at();
    """
  end

  def down do
    execute "DROP FUNCTION message_media_trigger() CASCADE;"
  end
end
