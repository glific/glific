defmodule Glific.Repo.Migrations.AddSettingColumnInOrganization do
  use Ecto.Migration

  def up do
    alter table(:organizations) do
      add(:setting, :jsonb)
    end
  end

  def down do
    alter table(:organizations) do
      remove(:jsonb)
    end
  end
end
