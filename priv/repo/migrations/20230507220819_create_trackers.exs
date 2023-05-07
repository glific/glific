defmodule Glific.Repo.Migrations.CreateTrackers do
  use Ecto.Migration

  def change do
    create table(:trackers) do
      add :day, :date
      add :month, :date
      add :is_summary, :boolean
      add :counts, :map

      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "reference for the organization"

      timestamps(type: :utc_datetime)
    end

    create index(:trackers, [:day, :organization_id])
    create index(:trackers, [:month, :organization_id])
    create index(:trackers, :organization_id)
  end
end
