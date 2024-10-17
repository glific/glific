defmodule Glific.Repo.Migrations.FilesearchTables do
  use Ecto.Migration

  def change do
    create_vector_stores()
    create_assistants()
  end

  defp create_assistants do
    create table(:openai_assistants) do
      add :assistant_id, :string, null: false, comment: "Unique assistantId generated by openAI"

      add :name, :string, null: false, comment: "Name of the assistant"

      add :model, :string, null: false, comment: "OpenAI model version used by this assistant"

      add :instructions, :text, comment: "Prompt for the agent"

      add :temperature, :float, comment: "model determinism range from 0 to 2"

      add :vector_store_id, references(:openai_vector_stores, on_delete: :nilify_all),
        comment: "Unique VectorStore id"

      # Foreign key to organization, restricting the scope of this table to the specified organization.
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      timestamps(type: :utc_datetime)
    end

    create unique_index(:openai_assistants, [:assistant_id, :organization_id])
    create unique_index(:openai_assistants, [:name, :organization_id])
  end

  defp create_vector_stores() do
    create table(:openai_vector_stores) do
      add :vector_store_id, :string,
        null: false,
        comment: "Unique VectorStore id generated by openAI"

      add :name, :string, null: false, comment: "Name of the VectorStore"

      add :files, :map, default: %{}, comment: "Map of fileId and its details"

      # Foreign key to organization, restricting the scope of this table to the specified organization.
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."

      add :size, :bigint, default: 0, comment: "Size of the vectorStore"

      add :status, :string,
        default: "in_progress",
        comment:
          "The readiness state of VectorStore, any of the given statuses - in_progress, completed, cancelled"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:openai_vector_stores, [:vector_store_id, :organization_id])
    create unique_index(:openai_vector_stores, [:name, :organization_id])
  end
end
