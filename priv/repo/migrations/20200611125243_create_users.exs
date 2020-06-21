defmodule Glific.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :phone, :string, null: false
      add :password_hash, :string

      add :name, :string
      add :roles, {:array, :string}, default: ["none"]

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:phone])
  end
end
