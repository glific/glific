defmodule Glific.Repo.Migrations.TestMigration do
  use Ecto.Migration

  def change do
    create_test_table()
  end

  defp create_test_table() do
    create table(:test_sheet) do
      add :label, :string, null: false, comment: "Label of the sheet"
      add :url, :string, null: false, comment: "Sheet URL along with gid"
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end
  end
end
