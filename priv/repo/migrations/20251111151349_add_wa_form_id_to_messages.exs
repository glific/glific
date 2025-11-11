defmodule Glific.Repo.Migrations.AddWaFormIdToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :wa_form_id, references(:whatsapp_forms_responses, on_delete: :nilify_all)
    end

    create index(:messages, [:wa_form_id])
  end
end
