defmodule Glific.Repo.Migrations.AddCategoryChangeInSessionTemplateTable do
  use Ecto.Migration

  def change do
    alter table(:session_templates) do
      add :allow_template_category_change, :boolean, default: true
    end
  end
end
