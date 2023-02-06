defmodule Glific.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:confirmed_at, :utc_datetime)
    end

    create table(:users_tokens) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:token, :binary, null: false)
      add(:context, :string, null: false)
      add(:sent_to, :string)
      add(:organization_id, references(:organizations, on_delete: :delete_all), null: false)
      timestamps(updated_at: false)
    end

    create(index(:users_tokens, [:user_id]))
    create(unique_index(:users_tokens, [:context, :token]))
  end
end
