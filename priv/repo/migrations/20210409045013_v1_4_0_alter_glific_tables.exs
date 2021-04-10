defmodule Glific.Repo.Migrations.V1_4_0_AlterGlificTables do
  use Ecto.Migration
  @global_schema Application.fetch_env!(:glific, :global_schema)

  def change do
    users()
    languages()
    flows()
  end

  defp users do
    alter table(:users) do
      add :language_id, references(:languages, on_delete: :restrict, prefix: @global_schema),
        null: true,
        comment: "Foreign key for the language"
    end
  end

  defp languages do
    alter table(:languages, prefix: @global_schema) do
      add :localized, :boolean, default: false
    end
  end

  defp flows do
    alter table(:flows) do
      add :respond_other, :boolean, default: false
      add :respond_no_response, :boolean, default: false
    end
  end
end
