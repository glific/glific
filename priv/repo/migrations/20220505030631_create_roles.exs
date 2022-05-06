defmodule Glific.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  def change do
    create table(:roles) do
      add :label, :string
      add :description, :string
      add :is_reserved, :boolean, default: false, null: false

      timestamps()
    end
  end
end
