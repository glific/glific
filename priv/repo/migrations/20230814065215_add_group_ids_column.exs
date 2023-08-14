defmodule Glific.Repo.Migrations.AddGroupIdsColumn do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      add :group_ids, {:array, :integer}, default: []
    end
    alter table(:message_broadcasts) do
      add :group_ids, {:array, :integer}, default: []
    end
  end
end
