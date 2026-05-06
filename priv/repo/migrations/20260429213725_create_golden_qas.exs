defmodule Glific.Repo.Migrations.CreateGoldenQas do
  use Ecto.Migration

  def change do
    create table(:golden_qas) do
      add(:name, :string, null: false)
      add(:dataset_id, :integer, null: false)
      add(:duplication_factor, :integer, default: 1)
      add(:file_name, :string)
      add(:organization_id, references(:organizations, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:golden_qas, [:organization_id]))
    create(unique_index(:golden_qas, [:organization_id, :name]))
    create(index(:golden_qas, [:organization_id, :inserted_at]))
  end

  def down do
    drop_if_exists(table(:golden_qas))
  end
end
