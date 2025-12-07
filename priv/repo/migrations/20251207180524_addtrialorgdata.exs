defmodule Glific.Repo.Migrations.Addtrialorgdata do
  use Ecto.Migration

  def change do
    create table(:trial_org_data) do
      add :username, :string, null: false
      add :email, :string, null: false
      add :phone, :string, null: false
      add :organization_name, :string, null: false
      add :otp_entered, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:trial_org_data, [:phone, :email])
    create index(:trial_org_data, [:email])
    create index(:trial_org_data, [:phone])
  end
end
