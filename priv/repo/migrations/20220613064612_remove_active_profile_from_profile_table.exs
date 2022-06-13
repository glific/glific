defmodule Glific.Repo.Migrations.RemoveActiveProfileFromProfileTable do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      remove(:active_profile_id, :id)
    end
  end
end
