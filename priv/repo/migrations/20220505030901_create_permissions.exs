defmodule Glific.Repo.Migrations.CreatePermissions do
  use Ecto.Migration

  def change do
    create table(:permissions) do
      add :entity, :string

      timestamps()
    end
  end
end
