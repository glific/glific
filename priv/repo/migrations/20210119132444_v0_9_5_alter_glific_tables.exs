defmodule Glific.Repo.Migrations.V0_9_5_AlterGlificTables do
  use Ecto.Migration

  def change do
    tags()
  end

  defp tags do
    alter table(:tags) do
      modify :description, :text
    end
  end
end
