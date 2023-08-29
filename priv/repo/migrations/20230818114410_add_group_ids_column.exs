defmodule Glific.Repo.Migrations.AddGroupIdsColumn do
  use Ecto.Migration

  def change do
    alter table(:message_broadcast_contacts) do
      add :group_ids, {:array, :integer}, default: []
    end
  end
end
