defmodule Glific.Repo.Migrations.AddStatusEnumToUsers do
  use Ecto.Migration

  def change do
    execute("""
    CREATE TYPE user_status_enum AS ENUM ('active', 'expired')
    """)

    alter table(:users) do
      add :status, :user_status_enum,
        default: "active",
        null: false,
        comment: "Indicates whether the user account is active or expired"
    end
  end
end
