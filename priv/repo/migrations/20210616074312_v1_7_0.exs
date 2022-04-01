defmodule Glific.Repo.Migrations.V170 do
  use Ecto.Migration

  alias Glific.Enums.OrganizationStatus

  def up do
    alter_organization_with_status()
    alter_billing_with_tds()
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

  def alter_billing_with_tds do
    alter table(:billings) do
      add_if_not_exists(:deduct_tds, :boolean,
        default: false,
        comment: "check if we should deduct the tds or not"
      )

      add_if_not_exists(:tds_amount, :float,
        default: 0,
        comment: "% of tds deduction on principle amount"
      )
    end
  end

  def down do
    OrganizationStatus.drop_type()
  end
end
