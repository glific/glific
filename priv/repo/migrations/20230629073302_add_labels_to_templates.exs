defmodule Glific.Repo.Migrations.AddLabelsToTemplates do
  use Ecto.Migration

  def change do
    alter table(:session_templates) do
      add(:labels, :string, default: "", comment: "Labels to search Session Templates")
    end
  end
end
