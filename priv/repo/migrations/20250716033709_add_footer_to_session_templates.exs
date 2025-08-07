defmodule Glific.Repo.Migrations.AddFooterToSessionTemplates do
  use Ecto.Migration

  def change do
    alter table(:session_templates) do
      add :footer, :string
    end
  end
end
