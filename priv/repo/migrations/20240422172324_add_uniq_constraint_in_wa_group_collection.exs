defmodule Glific.Repo.Migrations.AddUniqConstraintInWaGroupCollection do
  use Ecto.Migration

  def change do
    create unique_index(:wa_groups_collections, [:wa_group_id, :group_id, :organization_id])
  end
end
