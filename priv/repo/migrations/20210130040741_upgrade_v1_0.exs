defmodule Glific.Repo.Migrations.UpgradeV10 do
  use Ecto.Migration

  def change do
    indexes()
  end

  defp indexes do
    create index(:contacts, :status)
    create index(:messages, :message_number)
    create unique_index(:messages, [:bsp_message_id, :organization_id])
  end
end
