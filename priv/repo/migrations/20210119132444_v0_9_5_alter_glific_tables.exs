defmodule Glific.Repo.Migrations.V0_9_5_AlterGlificTables do
  use Ecto.Migration

  def change do
    tags()
    languages()
    groups()
  end

  defp tags do
    alter table(:tags) do
      modify :description, :text
    end
  end

  defp languages do
    alter table(:languages) do
      modify :description, :text
    end
  end

  defp groups do
    alter table(:groups) do
      modify :description, :text
    end
  end
end
