defmodule Glific.Repo.Migrations.AddGroupIdsColumnInTriggerTable do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      add :group_ids, {:array, :integer}, default: []
    end
  end
end
