defmodule Glific.Repo.Migrations.V0_7_1_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.6.2 Alter Glific tables
  """

  alias Glific.{
    Groups.UserGroup,
    Groups.ContactGroup,
    Tags.ContactTag,
    Tags.MessageTag,
    Tags.TemplateTag,
    Repo
  }

  import Ecto.Query, warn: false

  def change do
    add_organization_id()
  end

  defp add_organization_id do
    # foreign key to organization restricting scope of this table to this organization only
    # keeping the field nullable so that migration can run with production data

    alter table(:users_groups) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: true
    end

    alter table(:contacts_groups) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: true
    end

    alter table(:contacts_tags) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: true
    end

    alter table(:messages_tags) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: true
    end

    alter table(:templates_tags) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: true
    end

    # Flush and update organization id of existing data
    flush()
    update_org_id_of_join_tables()

    # Modify the field to not nullable
    alter table(:users_groups) do
      modify :organization_id, :bigint, null: false
    end

    alter table(:contacts_groups) do
      modify :organization_id, :bigint, null: false
    end

    alter table(:contacts_tags) do
      modify :organization_id, :bigint, null: false
    end

    alter table(:messages_tags) do
      modify :organization_id, :bigint, null: false
    end

    alter table(:templates_tags) do
      modify :organization_id, :bigint, null: false
    end
  end

  defp update_org_id_of_join_tables do
    from([fc] in UserGroup,
      join: f in assoc(fc, :group),
      update: [set: [organization_id: f.organization_id]]
    )
    |> Repo.update_all([], skip_organization_id: true)

    from([fc] in ContactGroup,
      join: f in assoc(fc, :group),
      update: [set: [organization_id: f.organization_id]]
    )
    |> Repo.update_all([], skip_organization_id: true)

    from([fc] in ContactTag,
      join: f in assoc(fc, :tag),
      update: [set: [organization_id: f.organization_id]]
    )
    |> Repo.update_all([], skip_organization_id: true)

    from([fc] in MessageTag,
      join: f in assoc(fc, :tag),
      update: [set: [organization_id: f.organization_id]]
    )
    |> Repo.update_all([], skip_organization_id: true)

    from([fc] in TemplateTag,
      join: f in assoc(fc, :tag),
      update: [set: [organization_id: f.organization_id]]
    )
    |> Repo.update_all([], skip_organization_id: true)
  end
end
