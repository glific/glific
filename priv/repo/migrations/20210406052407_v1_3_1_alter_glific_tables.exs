defmodule Glific.Repo.Migrations.V131AlterGlificTables do
  use Ecto.Migration
  @global_schema Application.fetch_env!(:glific, :global_schema)

  def change do
    session_templates()
  end

  defp session_templates() do
    alter table(:session_templates) do
      modify :example, :text, null: true
    end
  end
end
