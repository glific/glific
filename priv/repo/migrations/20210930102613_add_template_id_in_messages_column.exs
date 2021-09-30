defmodule Glific.Repo.Migrations.AddTemplateIdInMessagesColumn do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :template_id, references(:session_templates, on_delete: :nilify_all),
        null: true,
        comment: "reference for the HSM template"
    end

    alter table(:messages) do
      add :interactive_template_id, references(:interactive_templates, on_delete: :nilify_all),
        null: true,
        comment: "reference for the interative message template"
    end

    create_if_not_exists index(:messages, :template_id, where: "template_id IS NOT NULL")

    create_if_not_exists index(:interactive_templates, :interactive_template_id,
                           where: "interactive_template_id IS NOT NULL"
                         )
  end
end
