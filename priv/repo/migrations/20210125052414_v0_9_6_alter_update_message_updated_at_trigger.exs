defmodule Glific.Repo.Migrations.V0_9_6_AlterUpdateMessageUpdatedAtTrigger do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION update_message_updated_at()
      RETURNS trigger AS $$

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
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER update_message_updated_at_trigger
    AFTER INSERT OR DELETE OR UPDATE
    ON messages_tags
    FOR EACH ROW
    EXECUTE PROCEDURE update_message_updated_at();
    """
  end

  def down do
    execute "DROP FUNCTION update_message_updated_at() CASCADE;"
  end
end
