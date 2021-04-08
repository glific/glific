defmodule Glific.Repo.Migrations.V131AlterGlificTables do
  use Ecto.Migration
  @global_schema Application.fetch_env!(:glific, :global_schema)

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
      add :language_id, references(:languages, on_delete: :restrict, prefix: @global_schema),
        null: true,
        comment: "Foreign key for the language"
    end
  end

  defp languages() do
    alter table(:languages, prefix: @global_schema) do
      add :localized, :boolean, default: false
    end
  end
end
