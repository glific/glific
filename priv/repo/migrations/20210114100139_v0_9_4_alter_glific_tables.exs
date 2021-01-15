defmodule Glific.Repo.Migrations.V0_9_4_AlterGlificTables do
  use Ecto.Migration

  def change do
    flow_contexts()
  end

  defp flow_contexts do
    alter table(:flow_contexts) do
      add :wait_for_time, :boolean, default: false
    end
  end
end
