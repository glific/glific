defmodule Glific.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  def change do
    create table(:roles) do
      add :label, :string
      add :description, :string
      add :is_reserved, :boolean, default: false, null: false

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID"

      timestamps()
    end

    create unique_index(:roles, [:label, :organization_id])
  end
end
