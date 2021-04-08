defmodule Glific.Repo.Migrations.V131AlterGlificTables do
  use Ecto.Migration

  def change do
    session_templates()
    users()
    languages()
  end

  defp session_templates() do
    alter table(:session_templates) do
      modify :example, :text, null: true
    end
  end

  defp users() do
    alter table(:users) do
      add :language_id, references(:languages, on_delete: :nothing), default: null
    end
  end

  defp languages() do
    alter table(:languages) do
      add :localized, :boolean, default: false
    end
  end
end
