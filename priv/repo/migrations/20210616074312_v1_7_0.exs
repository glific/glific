defmodule Glific.Repo.Migrations.V170 do
  use Ecto.Migration

  alias Glific.Enums.OrganizationStatus

  def up do
    alter_organization_with_status()
  end

  def alter_organization_with_status do
    OrganizationStatus.create_type()

    alter table(:organizations) do
      add_if_not_exists(:status, :organization_status_enum,
        default: "inactive",
        comment: "organization status to define different states of the organizations"
      )
    end
  end

  def down do
    OrganizationStatus.drop_type()
  end
end
