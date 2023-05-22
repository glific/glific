defmodule Glific.Repo.Migrations.CreateTopic do
  use Ecto.Migration

  def change do
    create table(:topics) do
      add :uuid, :uuid, null: false, comment: "Unique ID for each topic"
      add :name, :string, comment: "Name of the topic"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:topics, [:name, :organization_id])
  end
end
