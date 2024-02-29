defmodule Glific.Repo.Migrations.AddWaGroupIdToTrigger do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      add :wa_group_ids, {:array, :integer}, default: []
    end

    alter table(:message_broadcasts) do
      add :wa_group_ids, {:array, :integer}, default: []
    end
  end
end
