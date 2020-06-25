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

    users_groups()
  end

  @doc """
  The join table between users and groups
  """
  def users_groups do
    create table(:users_groups) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :group_id, references(:groups, on_delete: :delete_all), null: false
    end

    create unique_index(:users_groups, [:user_id, :group_id])
  end
end
