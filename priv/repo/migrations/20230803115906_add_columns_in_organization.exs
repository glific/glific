defmodule Glific.Repo.Migrations.AddSettingColumnInOrganization do
  use Ecto.Migration

  def up do
    alter table(:organizations) do
      add(:parent_org, :varchar)
      add(:setting, :jsonb)
    end
  end

  def down do
    alter table(:organizations) do
      remove(:parent_org)
      remove(:setting)
    end
  end
end
