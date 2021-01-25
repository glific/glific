defmodule Glific.Repo.Migrations.V0_9_6_AlterContactUpdateUpdatedAtOnTaggingTrigger do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION update_contact_updated_at_on_tagging()
      RETURNS trigger AS $$

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
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER update_contact_updated_at_on_tagging_trigger
    AFTER INSERT OR DELETE OR UPDATE
    ON contacts_tags
    FOR EACH ROW
    EXECUTE PROCEDURE update_contact_updated_at_on_tagging();
    """
  end

  def down do
    execute "DROP FUNCTION update_contact_updated_at_on_tagging() CASCADE;"
  end
end
