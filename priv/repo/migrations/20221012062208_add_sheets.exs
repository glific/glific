defmodule Glific.Repo.Migrations.AddSheets do
  use Ecto.Migration

  def change do
    create_sheets()
    create_sheets_data()
  end

  defp create_sheets() do
    create table(:sheets) do
      add :label, :string, null: false, comment: "Label of the sheet"
      add :url, :string, null: false, comment: "Sheet URL along with gid"

      add :synced_at, :utc_datetime,
        default: fragment("NOW()"),
        comment: "Time when the sheet was synced at"

      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end
  end

  defp create_sheets_data() do
    create table(:sheets_data) do
      add :key, :string, null: false, comment: "Row's Key of the referenced sheet"
      add :data, :map, default: %{}, comment: "Sheet's row level data saved from last sync"
      add :sheet_id, references(:sheets, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end
  end
end
