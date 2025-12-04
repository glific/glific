defmodule Glific.Repo.Migrations.AddRevisionIdToWhatsappForms do
  use Ecto.Migration

  def change do
    alter table(:whatsapp_forms) do
      add :revision_id, references(:whatsapp_form_revisions, on_delete: :nilify_all)
    end
  end
end
