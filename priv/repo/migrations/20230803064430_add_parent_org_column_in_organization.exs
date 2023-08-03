defmodule Glific.Repo.Migrations.AddParentOrgColumnInOrganization do
  use Ecto.Migration

  def up do
    alter table(:organizations) do
      add(:parent_org, :varchar)
    end
  end

  def down do
    alter table(:organizations) do
      remove(:varchar)
    end
  end
end
