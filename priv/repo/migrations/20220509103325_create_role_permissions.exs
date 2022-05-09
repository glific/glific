defmodule Glific.Repo.Migrations.CreateRolePermissions do
  use Ecto.Migration
  @global_schema Application.fetch_env!(:glific, :global_schema)

  def change do
    create table(:role_permissions) do
      add :role_id, references(:roles, on_delete: :delete_all), null: false

      add :permission_id,
          references(:permissions, on_delete: :delete_all, prefix: @global_schema),
          null: false

      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
    end

    create unique_index(:role_permissions, [:role_id, :permission_id, :organization_id])
  end
end
