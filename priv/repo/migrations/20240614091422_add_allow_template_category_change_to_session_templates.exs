defmodule Glific.Repo.Migrations.AddAllowTemplateCategoryChangeToSessionTemplates do
  use Ecto.Migration

  def change do
    alter table(:session_templates) do
      add :allow_template_category_change, :boolean, default: true, null: true
    end
  end
end
