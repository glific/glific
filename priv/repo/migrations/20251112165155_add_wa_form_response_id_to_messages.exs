defmodule Glific.Repo.Migrations.AddWaFormResponseIdToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :whatsapp_form_response_id, references(:whatsapp_forms_responses, on_delete: :nilify_all)
    end

    create index(:messages, [:whatsapp_form_response_id])
  end
end
