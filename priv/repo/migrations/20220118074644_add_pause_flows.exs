defmodule Glific.Repo.Migrations.AddPauseFlows do
  use Ecto.Migration

  def change do
    flow_contexts()
  end

  defp flow_contexts do
    alter table(:flow_contexts) do
      add :is_flow_paused, :boolean,
        default: false,
        comment: "Is the flow context in paused state"
    end
  end
end
