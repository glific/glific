defmodule Glific.Repo.Migrations.ValidateVersionsOrganizationFk do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE versions VALIDATE CONSTRAINT versions_organization_id_fkey")
  end

  def down, do: :ok
end
