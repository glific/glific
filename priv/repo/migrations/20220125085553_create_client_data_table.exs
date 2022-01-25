defmodule Glific.Repo.Migrations.CreateClientDataTable do
  use Ecto.Migration

  def change do
    client_data_table()
  end

  def client_data_table do
    create table(:client_data) do
      add(:key, :string, null: false)
      add(:descriptioon, :string)
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
