defmodule Glific.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :phone, :string, null: false
      add :password_hash, :string

      timestamps()
    end

    create unique_index(:users, [:phone])
  end
end
