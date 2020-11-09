defmodule Glific.Repo.Migrations.V0_7_0_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.7.0 Alter Glific tables
  """

  def change do
    add_organization_id()
  end

  defp add_organization_id do
    # foreign key to organization restricting scope of this table to this organization only
    # keeping the field nullable so that migration can run with production data

    alter table(:users_groups) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
    end

    alter table(:contacts_groups) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
    end

    alter table(:contacts_tags) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
    end

    alter table(:messages_tags) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
    end

    alter table(:templates_tags) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
    end
  end
end
