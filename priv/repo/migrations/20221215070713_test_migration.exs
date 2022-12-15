defmodule Glific.Repo.Migrations.TestMigration do
  use Ecto.Migration

  def change do
    build_test_v1()
  end

  defp build_test_v1() do
    create table(:build_test_v1) do
      add :label, :string, null: false, comment: "Label of the sheet"
      add :url, :string, null: false, comment: "Sheet URL along with gid"

      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end
  end
end
