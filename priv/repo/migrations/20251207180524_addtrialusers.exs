defmodule Glific.Repo.Migrations.AddtrialUser do
  use Ecto.Migration

  def change do
    create table(:trial_users) do
      add :username, :string, null: false
      add :email, :string, null: false
      add :phone, :string, null: false
      add :organization_name, :string, null: false
      add :otp_entered, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:trial_users, [:phone])
    create unique_index(:trial_users, [:email])
  end
end
