defmodule Glific.Repo.Migrations.CreateOrganizationDataTable do
  use Ecto.Migration

  def change do
    organization_data_table()
  end

  def organization_data_table do
    create table(:organization_data) do
      add(:key, :string, null: false)
      add(:description, :string)
      add(:json, :map, default: %{})
      add(:text, :text)

      # foreign key to organization restricting scope of this table to this organization only
      add(:organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organisation ID"
      )

      timestamps(type: :utc_datetime)
    end
  end
end
