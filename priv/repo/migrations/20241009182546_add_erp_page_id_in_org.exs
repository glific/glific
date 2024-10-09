defmodule Glific.Repo.Migrations.AddErpPageIdInOrg do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :erp_page_id, :string, comment: "ID of the org's row in ERP's customer-list database"
    end
  end
end
