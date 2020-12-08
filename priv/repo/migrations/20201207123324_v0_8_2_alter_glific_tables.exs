defmodule Glific.Repo.Migrations.V0_8_2_AlterGlificTables do
  use Ecto.Migration

  def change do
    add_indexes()
  end

  defp add_indexes() do
    # index to improve time of flow activity API
    create index(:flow_counts, [:organization_id, :flow_uuid])
    # index to improve search query for all in chat page
    create index(:messages, [:organization_id, :id, :contact_id])
  end
end
