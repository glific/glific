defmodule Glific.Repo.Migrations.UserLastLogin do
  use Ecto.Migration

  def change do
    users()
  end

  defp users() do
    alter table(:users) do
      add :last_login_at, :utc_datetime, default: nil
      add :last_login_from, :utc_datetime, default: nil
    end
  end
end
