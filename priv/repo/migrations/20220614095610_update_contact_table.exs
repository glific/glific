defmodule Glific.Repo.Migrations.UpdateContactTable do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      remove(:active_profile_id, :id)
    end

    alter table(:contacts) do
      add :active_profile_id, references(:profiles, on_delete: :nilify_all), null: true
    end
  end
end
