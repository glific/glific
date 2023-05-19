defmodule Glific.Repo.Migrations.CreateTrackers do
  use Ecto.Migration

  def change do
    create table(:trackers) do
      add(:period, :string, comment: "The period for this record: day or month")

      add(:date, :date,
        comment:
          "All events are measured with respect to UTC time, to keep things timezone agnostic"
      )

      add(:counts, :map)

      add(:organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "reference for the organization"
      )

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:trackers, [:date, :period, :organization_id]))
    create(index(:trackers, :organization_id))
  end
end
