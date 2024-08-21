defmodule Glific.Repo.Migrations.AddAssistantInfo do
  use Ecto.Migration

  def change do
    create_assistant_record()
  end

  defp create_assistant_record do
    create table(:openai_assistant) do
      add :assistant_id, :string

      add :assistant_name, :string

      add :has_vector_store, :boolean, default: false

      add :model, :string

      add :vector_store_id, :string

      add :description, :string

      add :instructions, :string

      # Foreign key to organization, restricting the scope of this table to the specified organization.
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."
    end
  end
end
