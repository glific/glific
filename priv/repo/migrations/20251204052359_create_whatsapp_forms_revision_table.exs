defmodule Glific.Repo.Migrations.CreateWhatsappFormsRevisionTable do
  use Ecto.Migration

  def change do
    create table(:whatsapp_form_revisions) do
      add :revision_number, :integer, null: false
      add :definition, :map, null: false
      add :whatsapp_form_id, references(:whatsapp_forms, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all), null: false

      timestamps()
    end

    create index(:whatsapp_form_revisions, [:whatsapp_form_id])
    create index(:whatsapp_form_revisions, [:user_id])
  end
end
