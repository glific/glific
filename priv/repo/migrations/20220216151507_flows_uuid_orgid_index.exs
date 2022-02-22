defmodule Glific.Repo.Migrations.FlowsUuidOrgidIndex do
  use Ecto.Migration

  def change do
    flows()
  end

  defp flows do
    drop_if_exists index(:flows, :uuid)
    create unique_index(:flows, [:uuid, :organization_id])
  end
end
