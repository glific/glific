defmodule Glific.Repo.Migrations.AddBspCategoryToSessionTemplates do
  use Ecto.Migration

  def change do
    alter table(:session_templates) do
      add :bsp_category, :string
    end
  end
end
