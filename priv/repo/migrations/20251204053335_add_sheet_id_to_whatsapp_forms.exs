defmodule Glific.Repo.Migrations.AddSheetIdToWhatsappForms do
  use Ecto.Migration

  def change do
    alter table(:whatsapp_forms) do
      add :sheet_id, references(:sheets, on_delete: :nilify_all)
    end

    create unique_index(:whatsapp_forms, [:sheet_id])
  end
end
