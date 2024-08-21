defmodule Glific.Repo.Migrations.CreateVectorStoreRecord do
  use Ecto.Migration

  def change do
    create_vector_store_record()
  end

  defp create_vector_store_record do
    create table(:openai_vector_store) do
      add :vector_store_id, :string

      add :vector_store_name, :string

      add :has_assistant, :boolean, default: false

      add :assistant_counts, :integer, default: 0

      # Foreign key to organization, restricting the scope of this table to the specified organization.
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID."
    end
  end
end
