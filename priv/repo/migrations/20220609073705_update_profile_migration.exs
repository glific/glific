defmodule Glific.Repo.Migrations.UpdateProfileMigration do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :active_profile_id, references(:profiles, on_delete: :nilify_all), null: true
    end
  end
end
