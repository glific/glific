defmodule Glific.Repo.Migrations.AddFieldsInTermAndCond do
  use Ecto.Migration

  def change do
    alter table(:registrations) do
      add :is_disputed, :boolean,
        null: true,
        comment: "if the user disputed the T&C"

      add :erp_page_id, :string, comment: "ID of the org's row in ERP's customer-list database"
    end
  end
end
