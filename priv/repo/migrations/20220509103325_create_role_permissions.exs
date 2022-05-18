defmodule Glific.Repo.Migrations.CreateRolePermissions do
  use Ecto.Migration
  @global_schema Application.fetch_env!(:glific, :global_schema)

  def change do
    create_role()
    create_permission()
    create_role_permissions()
    create_role_flows()
    create_user_roles()
  end

  defp create_role() do
    create table(:roles) do
      add :label, :string
      add :description, :string
      add :is_reserved, :boolean, default: false, null: false

      # foreign key to organization restricting scope of this table to this organization only
      add(:organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID"
      )

      timestamps()
    end

    create unique_index(:roles, [:label, :organization_id])
  end

  defp create_permission() do
    create table(:permissions, prefix: @global_schema) do
      add :entity, :string

      timestamps()
    end
  end

  defp create_role_permissions() do
    create table(:role_permissions) do
      add :role_id, references(:roles, on_delete: :delete_all), null: false

      add :permission_id,
          references(:permissions, on_delete: :delete_all, prefix: @global_schema),
          null: false

      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
    end

    create unique_index(:role_permissions, [:role_id, :permission_id, :organization_id])
  end

  defp create_role_flows() do
    create table(:role_flows) do
      add :role_id, references(:roles, on_delete: :delete_all), null: false
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
    end

    create unique_index(:role_flows, [:role_id, :flow_id, :organization_id])
  end

  defp create_user_roles() do
    create table(:role_users) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role_id, references(:roles, on_delete: :delete_all), null: false
      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID"
    end

    create unique_index(:role_users, [:user_id, :role_id])
  end
end
