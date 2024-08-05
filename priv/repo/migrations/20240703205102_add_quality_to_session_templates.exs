defmodule Glific.Repo.Migrations.AddQualityToSessionTemplates do
  use Ecto.Migration

  def change do
    alter table(:session_templates) do
      add :quality, :string
    end
  end
end
