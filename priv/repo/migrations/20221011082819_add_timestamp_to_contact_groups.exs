defmodule Glific.Repo.Migrations.AddTimestampToContactGroups do
  use Ecto.Migration

  def change do
    alter table(:contacts_groups) do
      timestamps default: "2021-01-01 00:00:00", null: false
    end
  end
end
