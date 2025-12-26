defmodule Glific.Repo.Migrations.AddRevisionIdToWhatsappForms do
  use Ecto.Migration

  def change do
    alter table(:whatsapp_forms) do
      add(:revision_id, references(:whatsapp_form_revisions, on_delete: :restrict))
    end

    create(index(:whatsapp_forms, [:revision_id]))
  end
end
