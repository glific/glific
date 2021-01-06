defmodule Glific.Repo.Migrations.V0_9_0_AlterGlificTables do
  use Ecto.Migration

  def change do
    last_communication_at()
  end

  defp last_communication_at() do
    alter table(:organizations) do
      add :last_communication_at, :utc_datetime
    end
  end
end
