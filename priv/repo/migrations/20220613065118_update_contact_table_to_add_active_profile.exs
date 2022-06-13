defmodule Glific.Repo.Migrations.UpdateContactTableToAddActiveProfile do
  use Ecto.Migration

  def change do
    alter table(:contacts) do
      add :active_profile_id, references(:profiles, on_delete: :nilify_all), null: true
    end
  end
end
