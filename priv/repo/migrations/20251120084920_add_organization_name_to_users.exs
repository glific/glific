defmodule Glific.Repo.Migrations.AddOrganizationNameToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :organization_name, :string
    end
  end

  def down do
    alter table(:users) do
      remove :organization_name
    end
  end
end
