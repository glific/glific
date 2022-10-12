defmodule Glific.Repo.Migrations.AddSheets do
  use Ecto.Migration

  def change do
    create table(:sheets) do
      add :label, :string, null: false, comment: "Label of the sheet"
      add :url, :string, null: false, comment: "Sheet URL along with gid"
      add :data, :map, default: %{}, comment: "Sheet data saved from last sync"
      add :synced_at, :utc_datetime, comment: "Time when the sheet was synced at"
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end
  end
end
