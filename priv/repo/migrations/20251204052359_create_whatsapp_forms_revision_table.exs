defmodule Glific.Repo.Migrations.CreateWhatsappFormsRevisionTable do
  use Ecto.Migration

  def up do
    create table(:whatsapp_form_revisions) do
      add :revision_number, :integer, null: false
      add :definition, :map, null: false
      add :whatsapp_form_id, references(:whatsapp_forms, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:whatsapp_form_revisions, [:whatsapp_form_id])
    create index(:whatsapp_form_revisions, [:user_id])

    execute """
    CREATE OR REPLACE FUNCTION set_whatsapp_form_revision_number()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      next_revision_number INTEGER;
    BEGIN
      IF NEW.revision_number IS NULL THEN
        SELECT COALESCE(MAX(revision_number), 0) + 1
        INTO next_revision_number
        FROM whatsapp_form_revisions
        WHERE whatsapp_form_id = NEW.whatsapp_form_id;

        NEW.revision_number := next_revision_number;
      END IF;
      RETURN NEW;
    END;
    $$;
    """

    execute """
    CREATE TRIGGER set_whatsapp_form_revision_number_trigger
    BEFORE INSERT ON whatsapp_form_revisions
    FOR EACH ROW
    EXECUTE FUNCTION set_whatsapp_form_revision_number();
    """
  end

  def down do
    execute """
    DROP TRIGGER IF EXISTS set_whatsapp_form_revision_number_trigger ON whatsapp_form_revisions;
    """

    execute """
    DROP FUNCTION IF EXISTS set_whatsapp_form_revision_number();
    """

    drop table(:whatsapp_form_revisions)
  end
end
