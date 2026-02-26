defmodule Glific.Repo.Migrations.MigrateWhatsappFormsDefinitionsToRevisions do
  use Ecto.Migration

  def up do
    # migrating existing form definitions from whatsapp_forms to whatsapp_form_revisions table
    execute("""
    INSERT INTO whatsapp_form_revisions (
      whatsapp_form_id,
      definition,
      user_id,
      organization_id,
      revision_number,
      inserted_at,
      updated_at
    )
    SELECT
      wf.id,
      wf.definition,
      COALESCE(
        (SELECT id FROM users WHERE organization_id = wf.organization_id LIMIT 1)
      ) as user_id,
      wf.organization_id,
      1 as revision_number,
      wf.inserted_at,
      wf.updated_at
    FROM whatsapp_forms wf
    WHERE wf.definition IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM whatsapp_form_revisions wfr
        WHERE wfr.whatsapp_form_id = wf.id
      );
    """)

    # updating whatsapp_forms to point to the newly created revisions
    execute("""
    UPDATE whatsapp_forms wf
    SET revision_id = wfr.id
    FROM whatsapp_form_revisions wfr
    WHERE wfr.whatsapp_form_id = wf.id
      AND wfr.revision_number = 1;
    """)

    # making definition field nullable in whatsapp_forms
    alter table(:whatsapp_forms) do
      modify(:definition, :jsonb, null: true)
    end
  end

  def down do
    # making definition field non-nullable in whatsapp_forms
    alter table(:whatsapp_forms) do
      modify(:definition, :jsonb, null: false)
    end
  end
end
