defmodule Glific.Repo.Migrations.AddUniqueIndexToAssistantTables do
  use Ecto.Migration

  def up do
    create unique_index(:assistants, [:name, :organization_id])
    create unique_index(:assistants, [:assistant_display_id, :organization_id])
    create unique_index(:knowledge_bases, [:name, :organization_id])
    create unique_index(:knowledge_base_versions, [:llm_service_id, :organization_id])
  end

  def down do
    drop_if_exists unique_index(:knowledge_base_versions, [:llm_service_id, :organization_id])
    drop_if_exists unique_index(:knowledge_bases, [:name, :organization_id])
    drop_if_exists unique_index(:assistants, [:assistant_display_id, :organization_id])
    drop_if_exists unique_index(:assistants, [:name, :organization_id])
  end
end
