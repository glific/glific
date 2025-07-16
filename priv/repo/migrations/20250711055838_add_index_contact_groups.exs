defmodule Glific.Repo.Migrations.AddIndexContactGroups do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:contacts_groups, [:group_id, :organization_id],
                           name: "contacts_groups_group_id_organization_id_index"
                         )
  end
end
