defmodule Glific.Repo.Migrations.AddIsActiveProfiles do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :is_active, :boolean,
        default: true,
        comment: "if the profile is deactivated then the value would be false else true"
    end
  end
end
