defmodule Glific.Repo.Migrations.CreateAccessControlList do
  use Ecto.Migration
  alias Glific.Enums.EntityType

  def up do
    EntityType.create_type()
    access_control()
    user_roles()
  end

  def down do
    EntityType.drop_type()
    drop_if_exists table(:access_control)
  end

  defp access_control() do
    create table(:access_control) do
      add :entity_id, :id

      add :entity_type, :entity_type_enum,
        null: false,
        comment: "Type of the entity: flow, trigger, search, template, interactive_template"

      add :role_id, references(:roles, on_delete: :delete_all),
        null: false,
        comment: "Unique roles corresponding to each entity_id"

      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID"

      timestamps()
    end

    create unique_index(:access_control, [:role_id, :entity_id, :organization_id])
  end

  defp user_roles() do
    create table(:users_roles) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role_id, references(:roles, on_delete: :delete_all), null: false
      # foreign key to organization restricting scope of this table to this organization only
      add :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        comment: "Unique organization ID"
    end

    create unique_index(:users_roles, [:user_id, :role_id])
  end
end
