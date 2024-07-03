defmodule Glific.Repo.Migrations.AddIsTemplateToFlows do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add :is_template, :boolean, default: false
    end
  end
end
