defmodule Glific.Repo.Migrations.V0_9_5_AlterGlificTables do
  @moduledoc """
  Updating description field as text
  """

  use Ecto.Migration

  @global_schema Application.fetch_env!(:glific, :global_schema)

  def change do
    tags()
    languages()
    groups()
    providers()
    session_templates()
  end

  defp tags do
    alter table(:tags) do
      modify :description, :text
    end
  end

  defp languages do
    alter table(:languages, prefix: @global_schema) do
      modify :description, :text
    end
  end

  defp groups do
    alter table(:groups) do
      modify :description, :text
    end
  end

  defp providers do
    alter table("providers", prefix: @global_schema) do
      modify :description, :text
    end
  end

  defp session_templates() do
    alter table(:session_templates) do
      modify :body, :text, null: true
    end
  end
end
