defmodule Glific.Repo.Migrations.CreateReports do
  use Ecto.Migration

  def change do
    create table(:reports) do
      add :name, :string
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps()
    end
  end
end
