defmodule Glific.Repo.Migrations.V131AlterGlificTables do
  use Ecto.Migration

  def change do
    session_templates()
  end

  defp session_templates() do
    alter table(:session_templates) do
      modify :example, :text, null: true
    end
  end
end
